import Foundation

// Note: FoundationModels is a future Apple Intelligence framework requiring iOS 26.0+ SDK.
// On iOS 17/18, use the fallback AIProvider implementation below.
#if canImport(FoundationModels) && ENABLE_FOUNDATION_MODELS_PREVIEW
import FoundationModels

public final class FoundationModelsProvider: AIProvider, @unchecked Sendable {
    public let id: String = "apple.foundation.models"
    public let displayName: String = "Apple Foundation Models (On-Device)"
    public let isGenerative: Bool = true
    
    private var session: LanguageModelSession?
    private var isCurrentlyGenerating: Bool = false
    private var currentTask: Task<Void, Never>?
    
    public init() {}
    
    public var modelState: AIModelState {
        if isCurrentlyGenerating {
            return .generating
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceDisabled
        case .unavailable:
            return .unavailable
        }
    }
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIProviderError.promptEmpty
        }
        
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw AIProviderError.serviceUnavailable("Device hardware is not eligible for on-device Apple Foundation Models.")
        case .unavailable(.modelNotReady):
            throw AIProviderError.serviceUnavailable("On-device model assets are not ready or are currently downloading.")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AIProviderError.serviceUnavailable("Apple Intelligence is disabled in System Settings.")
        case .unavailable(let reason):
            throw AIProviderError.serviceUnavailable("On-device model is unavailable: \(reason)")
        }
        
        isCurrentlyGenerating = true
        defer { isCurrentlyGenerating = false }
        
        try Task.checkCancellation()
        
        let activeSession = session ?? LanguageModelSession()
        self.session = activeSession
        
        let response = try await activeSession.respond(to: trimmed)
        try Task.checkCancellation()
        return response.content
    }
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    isCurrentlyGenerating = true
                    defer { isCurrentlyGenerating = false }
                    
                    let activeSession = session ?? LanguageModelSession()
                    self.session = activeSession
                    
                    let responseStream = activeSession.streamResponse(to: prompt)
                    
                    var lastYieldedLength = 0
                    for try await snapshot in responseStream {
                        if Task.isCancelled {
                            continuation.finish(throwing: AIProviderError.cancelled)
                            return
                        }
                        
                        let currentText = snapshot
                        if currentText.count > lastYieldedLength {
                            let startIndex = currentText.index(currentText.startIndex, offsetBy: lastYieldedLength)
                            let newPart = String(currentText[startIndex...])
                            continuation.yield(newPart)
                            lastYieldedLength = currentText.count
                        }
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
        isCurrentlyGenerating = false
    }
}

#else

// Fallback when compiling in an SDK that does not include the public FoundationModels framework
public final class FoundationModelsProvider: AIProvider, @unchecked Sendable {
    public let id: String = "apple.foundation.models.unavailable"
    public let displayName: String = "Apple Foundation Models (SDK Unavailable)"
    public let isGenerative: Bool = false
    
    public init() {}
    
    public var modelState: AIModelState {
        return .sdkUnavailable
    }
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        throw AIProviderError.serviceUnavailable(
            "The official Apple FoundationModels framework is not available in this SDK build. It requires iOS 26+."
        )
    }
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: AIProviderError.serviceUnavailable(
                    "The official Apple FoundationModels framework is not available in this SDK build. It requires iOS 26+."
                )
            )
        }
    }
    
    public func cancel() {}
}

#endif
