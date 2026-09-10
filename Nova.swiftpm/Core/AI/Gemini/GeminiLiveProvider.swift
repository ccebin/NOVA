import Foundation
import AVFoundation
import os

/// State machine for Gemini Live real-time bidirectional WebSocket sessions.
public enum GeminiLiveSessionState: Equatable, Sendable {
    case disconnected
    case connecting
    case ready
    case listening
    case speaking
    case interrupted
    case error(String)
}

/// Realtime voice provider using Gemini 3.1 Flash Live Preview over WebSockets.
/// Enforces setup handshake before audio streaming, handles 16kHz input / 24kHz output PCM audio,
/// implements barge-in interruption, and routes tool calls through ToolExecutor + VerificationGate.
public final class GeminiLiveProvider: @unchecked Sendable {
    public let configuration: GeminiConfiguration
    private let keyProvider: GeminiKeyProvider
    private let transport: GeminiWebSocketTransport
    private let logger = Logger(subsystem: "com.nova.assistant", category: "GeminiLiveProvider")
    
    private let stateLock = NSLock()
    private var _state: GeminiLiveSessionState = .disconnected
    private var isSetupComplete: Bool = false
    private var receiveLoopTask: Task<Void, Never>?
    
    public var onStateChange: (@Sendable (GeminiLiveSessionState) -> Void)?
    public var onAudioChunkReceived: (@Sendable (Data) -> Void)?
    public var onTextReceived: (@Sendable (String) -> Void)?
    public var onInterrupted: (@Sendable () -> Void)?
    
    public init(
        keyProvider: GeminiKeyProvider,
        transport: GeminiWebSocketTransport = URLSessionWebSocketGeminiTransport(),
        configuration: GeminiConfiguration = GeminiConfiguration()
    ) {
        self.keyProvider = keyProvider
        self.transport = transport
        self.configuration = configuration
    }
    
    public var state: GeminiLiveSessionState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }
    
    private func transition(to newState: GeminiLiveSessionState) {
        stateLock.lock()
        _state = newState
        let callback = onStateChange
        stateLock.unlock()
        callback?(newState)
    }
    
    // MARK: - Connection & Handshake
    
    public func startSession() async throws {
        stateLock.lock()
        guard _state == .disconnected || _state == .interrupted else {
            stateLock.unlock()
            return
        }
        _state = .connecting
        isSetupComplete = false
        stateLock.unlock()
        
        let apiKey: String
        do {
            apiKey = try await keyProvider.getApiKey()
        } catch {
            transition(to: .error("Missing Gemini API Key."))
            throw AIProviderError.authenticationFailed("Gemini API key is missing.")
        }
        
        // Official WebSocket endpoint with Google API key query/header
        var urlComponents = URLComponents(url: configuration.liveWebSocketURL, resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let finalURL = urlComponents.url else {
            transition(to: .error("Invalid WebSocket URL."))
            throw AIProviderError.serviceUnavailable("Invalid URL components.")
        }
        
        do {
            try await transport.connect(url: finalURL, headers: [:])
            startReceiveLoop()
            try await sendSetupMessage()
        } catch {
            transition(to: .error("Failed to connect: \(error.localizedDescription)"))
            throw error
        }
    }
    
    public func endSession() {
        stateLock.lock()
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        isSetupComplete = false
        stateLock.unlock()
        
        transport.disconnect()
        transition(to: .disconnected)
    }
    
    // MARK: - Handshake Setup Message
    
    private func sendSetupMessage() async throws {
        let toolDefs = ToolRegistry.shared.allDefinitions()
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
        
        let setupPayload: [String: Any] = [
            "setup": [
                "model": "models/\(configuration.liveModel)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Aoede"
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": NovaPersonality.shared.systemPrompt]
                    ]
                ],
                "tools": [
                    ["functionDeclarations": functionDeclarations]
                ]
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: setupPayload, options: [])
        let jsonString = String(data: data, encoding: .utf8)!
        try await transport.send(message: .string(jsonString))
    }
    
    // MARK: - Audio Input (16kHz 16-bit PCM)
    
    /// Streams a raw 16-bit 16kHz mono PCM audio chunk to the Gemini Live session.
    /// Setup handshake MUST be confirmed before audio is sent.
    public func sendAudioChunk(_ pcm16kData: Data) async throws {
        stateLock.lock()
        guard isSetupComplete else {
            stateLock.unlock()
            logger.warning("Attempted to send audio chunk before Gemini Live setupComplete. Chunk dropped.")
            return
        }
        stateLock.unlock()
        
        transition(to: .listening)
        
        let base64 = pcm16kData.base64EncodedString()
        let payload: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": GeminiConfiguration.liveInputMimeType,
                        "data": base64
                    ]
                ]
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let jsonString = String(data: data, encoding: .utf8)!
        try await transport.send(message: .string(jsonString))
    }
    
    // MARK: - WebSocket Receive Loop
    
    private func startReceiveLoop() {
        receiveLoopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await self.transport.receive()
                    try await self.handleIncomingMessage(message)
                } catch {
                    if !Task.isCancelled {
                        self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                        self.transition(to: .error(error.localizedDescription))
                    }
                    break
                }
            }
        }
    }
    
    public func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message) async throws {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:
            return
        }
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // 1. Setup Complete confirmation
        if json["setupComplete"] != nil {
            stateLock.lock()
            isSetupComplete = true
            stateLock.unlock()
            transition(to: .ready)
            return
        }
        
        // 2. Server Content (Audio / Text / Interruption)
        if let serverContent = json["serverContent"] as? [String: Any] {
            // Check for interruption (barge-in)
            if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
                transition(to: .interrupted)
                onInterrupted?()
                return
            }
            
            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                transition(to: .speaking)
                for part in parts {
                    // Raw 24kHz PCM Audio Chunk
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let base64Audio = inlineData["data"] as? String,
                       let audioData = Data(base64Encoded: base64Audio) {
                        onAudioChunkReceived?(audioData)
                    }
                    
                    // Transcribed text (if any)
                    if let textContent = part["text"] as? String {
                        onTextReceived?(textContent)
                    }
                }
            }
            
            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                transition(to: .ready)
            }
        }
        
        // 3. Tool Calls (Function Calling)
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            try await handleLiveToolCall(functionCalls: functionCalls)
        }
    }
    
    // MARK: - Tool Execution over Gemini Live
    
    /// Executes requested function calls on-device via ToolExecutor + VerificationGate
    /// and sends verified toolResponse back to Gemini Live.
    private func handleLiveToolCall(functionCalls: [[String: Any]]) async throws {
        var functionResponses: [[String: Any]] = []
        
        for call in functionCalls {
            guard let callId = call["id"] as? String,
                  let name = call["name"] as? String else {
                continue
            }
            
            let args = call["args"] as? [String: Any] ?? [:]
            
            // Execute on-device using NOVA's ToolRegistry & ToolExecutor
            var responseOutput: [String: Any] = [:]
            if let tool = ToolRegistry.shared.tool(for: name) {
                let toolArgs = ToolArguments(args)
                let result = await ToolExecutor.shared.execute(tool: tool, arguments: toolArgs, isUserConfirmed: true)
                
                let isVerified = result.verification?.isVerified ?? (result.status == .success)
                responseOutput = [
                    "status": result.status.rawValue,
                    "verified": isVerified,
                    "message": result.verification?.explanation ?? result.message,
                    "diffSummary": result.diff?.summary ?? ""
                ]
            } else {
                responseOutput = [
                    "status": "not_found",
                    "verified": false,
                    "message": "Tool '\(name)' is not registered on this device."
                ]
            }
            
            functionResponses.append([
                "id": callId,
                "name": name,
                "response": [
                    "output": responseOutput
                ]
            ])
        }
        
        let toolResponsePayload: [String: Any] = [
            "toolResponse": [
                "functionResponses": functionResponses
            ]
        ]
        
        let data = try JSONSerialization.data(withJSONObject: toolResponsePayload, options: [])
        let jsonString = String(data: data, encoding: .utf8)!
        try await transport.send(message: .string(jsonString))
    }
}
