import Foundation
import os

/// Gemini 3.8 Flash REST AIProvider conforming to ONE NOVA architecture.
/// Implements Free Tier operation, secure header authentication, thinking level control,
/// and normalization of HTTP 429 / RESOURCE_EXHAUSTED to quotaExceeded.
public final class GeminiProvider: AIProvider, @unchecked Sendable {
    public let id: String = "gemini_flash"
    public let displayName: String = "Gemini 3.8 Flash (Free Tier)"
    public let isGenerative: Bool = true
    
    private let keyProvider: GeminiKeyProvider
    private let transport: GeminiHTTPTransport
    private let configuration: GeminiConfiguration
    private let logger = Logger(subsystem: "com.nova.assistant", category: "GeminiProvider")
    
    private let stateLock = NSLock()
    private var _modelState: AIModelState = .ready
    private var currentTask: Task<String, Error>?
    
    public init(
        keyProvider: GeminiKeyProvider,
        transport: GeminiHTTPTransport = URLSessionGeminiTransport(),
        configuration: GeminiConfiguration = GeminiConfiguration()
    ) {
        self.keyProvider = keyProvider
        self.transport = transport
        self.configuration = configuration
    }
    
    public var modelState: AIModelState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _modelState
    }
    
    private func setModelState(_ newState: AIModelState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _modelState = newState
    }
    
    // MARK: - AIProvider Protocol Conformance
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIProviderError.promptEmpty
        }
        
        setModelState(.generating)
        defer { setModelState(.ready) }
        
        let apiKey: String
        do {
            apiKey = try await keyProvider.getApiKey()
        } catch {
            throw AIProviderError.authenticationFailed("Gemini API key is missing or inaccessible.")
        }
        
        let endpoint = configuration.baseURL
            .appendingPathComponent("models")
            .appendingPathComponent("\(configuration.textModel):generateContent")
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // Security Rule: Official header authentication. Key NEVER placed in URL query.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        let payload = try buildRequestBody(prompt: trimmed, history: history)
        request.httpBody = payload
        
        let sendTask = Task<String, Error> {
            try Task.checkCancellation()
            let (data, response) = try await self.transport.send(request: request)
            try Task.checkCancellation()
            return try self.parseResponse(data: data, httpResponse: response)
        }
        
        stateLock.lock()
        self.currentTask = sendTask
        stateLock.unlock()
        
        do {
            let result = try await sendTask.value
            return result
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch {
            throw error
        }
    }
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return AsyncThrowingStream { continuation in
            guard !trimmed.isEmpty else {
                continuation.finish(throwing: AIProviderError.promptEmpty)
                return
            }
            
            let task = Task {
                self.setModelState(.generating)
                defer { self.setModelState(.ready) }
                
                do {
                    let apiKey = try await self.keyProvider.getApiKey()
                    let endpoint = self.configuration.baseURL
                        .appendingPathComponent("models")
                        .appendingPathComponent("\(self.configuration.textModel):streamGenerateContent")
                    
                    var comp = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
                    comp.queryItems = [URLQueryItem(name: "alt", value: "sse")]
                    
                    var request = URLRequest(url: comp.url!)
                    request.httpMethod = "POST"
                    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    
                    let payload = try self.buildRequestBody(prompt: trimmed, history: history)
                    request.httpBody = payload
                    
                    for try await chunkData in self.transport.stream(request: request) {
                        try Task.checkCancellation()
                        if let text = self.extractTextFromSSE(data: chunkData) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    public func cancel() {
        stateLock.lock()
        currentTask?.cancel()
        currentTask = nil
        stateLock.unlock()
        setModelState(.ready)
    }
    
    // MARK: - Payload Construction
    
    public func buildRequestBody(prompt: String, history: [ChatMessage]) throws -> Data {
        var contents: [[String: Any]] = []
        
        // Format history into Gemini's user / model turn contract
        for msg in history {
            let role = (msg.role == .user) ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        
        // Append current user prompt
        contents.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])
        
        // System instruction respecting NOVA personality
        let systemInstruction: [String: Any] = [
            "parts": [
                ["text": NovaPersonality.shared.systemPrompt]
            ]
        ]
        
        // Generation configuration with official thinking_level parameter for Gemini 3.8
        let generationConfig: [String: Any] = [
            "temperature": configuration.temperature,
            "thinking_level": configuration.thinkingLevel.rawValue
        ]
        
        var body: [String: Any] = [
            "contents": contents,
            "systemInstruction": systemInstruction,
            "generationConfig": generationConfig
        ]
        
        // Add tools from ToolRegistry if available
        let toolDefs = ToolRegistry.shared.allDefinitions()
        if !toolDefs.isEmpty {
            let functionDeclarations = toolDefs.map { def -> [String: Any] in
                var decl: [String: Any] = [
                    "name": def.id,
                    "description": def.description
                ]
                var properties: [String: Any] = [:]
                var required: [String] = []
                for arg in def.arguments {
                    properties[arg.name] = [
                        "type": "STRING",
                        "description": arg.description
                    ]
                    if arg.isRequired {
                        required.append(arg.name)
                    }
                }
                decl["parameters"] = [
                    "type": "OBJECT",
                    "properties": properties,
                    "required": required
                ]
                return decl
            }
            body["tools"] = [
                ["functionDeclarations": functionDeclarations]
            ]
        }
        
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }
    
    // MARK: - Response Parsing & Quota Normalization
    
    public func parseResponse(data: Data, httpResponse: HTTPURLResponse) throws -> String {
        let errorMsg = extractErrorMessage(from: data)
        
        // 1. Quota / Rate-limit normalization (HTTP 429 or RESOURCE_EXHAUSTED / RATE_LIMIT_EXCEEDED)
        if httpResponse.statusCode == 429 || (errorMsg?.contains("RESOURCE_EXHAUSTED") ?? false) || (errorMsg?.contains("RATE_LIMIT_EXCEEDED") ?? false) {
            throw AIProviderError.quotaExceeded(errorMsg ?? "Gemini Free Tier rate limit or quota exceeded (HTTP 429).")
        }
        
        // 2. Authentication failure (HTTP 401, HTTP 403, or HTTP 400 with API_KEY_INVALID)
        let isAuthFailure = httpResponse.statusCode == 401 ||
                            httpResponse.statusCode == 403 ||
                            (errorMsg?.contains("API_KEY_INVALID") ?? false) ||
                            (errorMsg?.contains("API key not valid") ?? false)
        if isAuthFailure {
            throw AIProviderError.authenticationFailed(errorMsg ?? "Authentication failed. Check your Gemini API key.")
        }
        
        // 3. General non-200 error inspection
        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = errorMsg ?? "Gemini returned HTTP \(httpResponse.statusCode)."
            throw AIProviderError.serviceUnavailable(msg)
        }
        
        // 4. Parse candidates
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.executionFailed("Malformed JSON response from Gemini.")
        }
        
        // Check for Google error payload even on 200
        if let errorObj = json["error"] as? [String: Any] {
            let status = errorObj["status"] as? String ?? ""
            let message = errorObj["message"] as? String ?? "Unknown error"
            if status == "RESOURCE_EXHAUSTED" || message.contains("quota") || message.contains("RATE_LIMIT_EXCEEDED") {
                throw AIProviderError.quotaExceeded("RESOURCE_EXHAUSTED: \(message)")
            }
            throw AIProviderError.executionFailed("Gemini error: \(message)")
        }
        
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIProviderError.executionFailed("Gemini response did not contain candidates.")
        }
        
        // Extract text or functionCall
        var combinedText = ""
        for part in parts {
            if let text = part["text"] as? String {
                combinedText += text
            } else if let functionCall = part["functionCall"] as? [String: Any],
                      let name = functionCall["name"] as? String {
                // Return formatted representation of function call for the router loop
                let args = functionCall["args"] as? [String: Any] ?? [:]
                let argsJSON = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                combinedText += "TOOL_CALL: \(name)(\(argsJSON))"
            }
        }
        
        return combinedText
    }
    
    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errorObj = json["error"] as? [String: Any],
              let msg = errorObj["message"] as? String else {
            return nil
        }
        var full = msg
        if let details = errorObj["details"] as? [[String: Any]] {
            for d in details {
                if let reason = d["reason"] as? String {
                    full += " [\(reason)]"
                }
            }
        }
        return full
    }
    
    private func extractTextFromSSE(data: Data) -> String? {
        guard let rawString = String(data: data, encoding: .utf8) else { return nil }
        let lines = rawString.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data:") {
                let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard let jsonData = jsonStr.data(using: .utf8),
                      let dummyResponse = HTTPURLResponse(url: configuration.baseURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil),
                      let text = try? parseResponse(data: jsonData, httpResponse: dummyResponse) else {
                    continue
                }
                return text
            }
        }
        return nil
    }
}
