import Foundation

public final class DegradedFallbackProvider: AIProvider, @unchecked Sendable {
    public let id: String = "local.degraded.fallback"
    public let displayName: String = "Standalone Local Mode (Non-Generative)"
    public let isGenerative: Bool = false
    
    private var currentTask: Task<Void, Never>?
    
    public init() {}
    
    public var modelState: AIModelState {
        return .sdkUnavailable
    }
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        try Task.checkCancellation()
        
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            throw AIProviderError.promptEmpty
        }
        
        let report = CapabilityDetector.shared.detectCapabilities()
        
        // Transparent, honest local responses without pretending to be an LLM
        if trimmed.contains("status") || trimmed.contains("capabilities") {
            return """
            [System Status - Standalone Mode]
            • Generative AI: Unavailable in this SDK build
            • Detail: \(report.foundationModelsCapability.explanation)
            • OS Version: iOS \(report.osCapability.osVersionString)
            • Memory: \(String(format: "%.1f", report.hardwareCapability.physicalMemoryGB)) GB
            • Local Storage: SwiftData active on iPhone
            • Network: None (Zero-network offline mode)
            """
        } else if trimmed == "help" {
            return """
            [NOVA Standalone Assistant]
            Generative AI (Foundation Models) is not available in this SDK build.
            
            Available local utilities:
            • Type "status" to inspect hardware & OS capability diagnostics
            • Messages are securely saved to your local SwiftData database
            • Review your system capabilities in the Settings tab
            """
        } else {
            return """
            [Generative AI Unavailable]
            NOVA is operating in offline Standalone Mode because public on-device Foundation Models are not available in this build (\(report.foundationModelsCapability.explanation)).

            Your message has been saved to local memory. Natural Language heuristics and local tools will be integrated in subsequent phases without relying on external servers.
            """
        }
    }
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await generateResponse(prompt: prompt, history: history)
                    let words = response.components(separatedBy: " ")
                    for (index, word) in words.enumerated() {
                        if Task.isCancelled {
                            continuation.finish(throwing: AIProviderError.cancelled)
                            return
                        }
                        let token = (index == 0 ? "" : " ") + word
                        continuation.yield(token)
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: AIProviderError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            
            self.currentTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
