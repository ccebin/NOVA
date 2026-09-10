import Foundation
import Combine
import os

/// Policy controlling which inference engine NOVA routes prompts to.
public enum EngineRoutingPolicy: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case gemini = "gemini"
    case smolLM2 = "smollm2"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .auto:
            return "Auto (Gemini Flash with On-Device SmolLM2 Fallback)"
        case .gemini:
            return "Gemini 3.8 Flash (Cloud Only — Free Tier)"
        case .smolLM2:
            return "SmolLM2-360M (Local Core ML Only)"
        }
    }
}

/// Policy controlling voice conversation mode.
public enum VoiceRoutingPolicy: String, CaseIterable, Identifiable, Sendable {
    case geminiLive = "gemini_live"
    case localVoice = "local_voice"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .geminiLive:
            return "Gemini 3.1 Flash Live (Realtime WebSocket Voice)"
        case .localVoice:
            return "NOVA On-Device Voice (Native Speech Engine)"
        }
    }
}

/// The ONE NOVA Inference Engine Router.
/// Manages unified routing across Gemini 3.8 Flash and SmolLM2 Core ML.
/// In .auto mode: seamlessly falls back to SmolLM2 on quota/rate-limit/network failure.
/// In .gemini mode: strictly surfaces errors without fallback.
/// In .smolLM2 mode: executes completely offline on-device.
public final class InferenceEngineRouter: AIProvider, ObservableObject, @unchecked Sendable {
    public let id: String = "inference_engine_router"
    
    public var displayName: String {
        switch policy {
        case .auto:
            return "NOVA Auto Router (Gemini + SmolLM2)"
        case .gemini:
            return "Gemini 3.8 Flash (Free Tier)"
        case .smolLM2:
            return "SmolLM2-360M-Instruct (Core ML)"
        }
    }
    
    public var isGenerative: Bool { true }
    
    public let geminiProvider: GeminiProvider
    public let smolLM2Provider: SmolLM2Provider
    public let geminiLiveProvider: GeminiLiveProvider
    
    private let logger = Logger(subsystem: "com.nova.assistant", category: "EngineRouter")
    private let lock = NSLock()
    
    private var _policy: EngineRoutingPolicy = .auto
    private var _voicePolicy: VoiceRoutingPolicy = .localVoice
    
    @Published public private(set) var lastFallbackReason: String? = nil
    @Published public private(set) var isCurrentlyFallback: Bool = false
    
    public init(
        geminiProvider: GeminiProvider,
        smolLM2Provider: SmolLM2Provider,
        geminiLiveProvider: GeminiLiveProvider,
        initialPolicy: EngineRoutingPolicy = .auto,
        initialVoicePolicy: VoiceRoutingPolicy = .localVoice
    ) {
        self.geminiProvider = geminiProvider
        self.smolLM2Provider = smolLM2Provider
        self.geminiLiveProvider = geminiLiveProvider
        self._policy = initialPolicy
        self._voicePolicy = initialVoicePolicy
    }
    
    public var policy: EngineRoutingPolicy {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _policy
        }
        set {
            lock.lock()
            _policy = newValue
            _ = lastFallbackReason
            lock.unlock()
            DispatchQueue.main.async {
                self.lastFallbackReason = nil
                self.isCurrentlyFallback = false
            }
        }
    }
    
    public var voicePolicy: VoiceRoutingPolicy {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _voicePolicy
        }
        set {
            lock.lock()
            _voicePolicy = newValue
            lock.unlock()
        }
    }
    
    public var modelState: AIModelState {
        switch policy {
        case .auto:
            if isCurrentlyFallback {
                return smolLM2Provider.modelState
            }
            return geminiProvider.modelState
        case .gemini:
            return geminiProvider.modelState
        case .smolLM2:
            return smolLM2Provider.modelState
        }
    }
    
    // MARK: - Prompt Generation Execution
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        switch policy {
        case .smolLM2:
            logger.info("Routing prompt directly to on-device SmolLM2 (Policy: .smolLM2).")
            return try await smolLM2Provider.generateResponse(prompt: prompt, history: history)
            
        case .gemini:
            logger.info("Routing prompt directly to Gemini 3.8 Flash (Policy: .gemini).")
            // No fallback allowed in .gemini mode. True error surfaced directly.
            return try await geminiProvider.generateResponse(prompt: prompt, history: history)
            
        case .auto:
            logger.info("Routing prompt via .auto policy (Attempting Gemini Flash first).")
            do {
                let response = try await geminiProvider.generateResponse(prompt: prompt, history: history)
                DispatchQueue.main.async {
                    self.lastFallbackReason = nil
                    self.isCurrentlyFallback = false
                }
                return response
            } catch let err as AIProviderError {
                let reasonString: String
                switch err {
                case .quotaExceeded(let reason):
                    reasonString = "quotaExceeded (\(reason))"
                case .rateLimited(let reason):
                    reasonString = "rateLimited (\(reason))"
                case .networkUnavailable(let reason):
                    reasonString = "networkUnavailable (\(reason))"
                case .authenticationFailed(let reason):
                    reasonString = "authenticationFailed (\(reason))"
                case .cancelled:
                    throw err
                default:
                    reasonString = err.localizedDescription
                }
                
                logger.warning("Gemini unavailable [\(reasonString)] → Falling back to on-device SmolLM2.")
                DispatchQueue.main.async {
                    self.lastFallbackReason = "Gemini unavailable (\(reasonString)) → SmolLM2 fallback"
                    self.isCurrentlyFallback = true
                }
                
                // Real fallback to SmolLM2. Never generate fake response!
                return try await smolLM2Provider.generateResponse(prompt: prompt, history: history)
            } catch {
                let reasonString = error.localizedDescription
                logger.warning("Gemini general failure [\(reasonString)] → Falling back to on-device SmolLM2.")
                DispatchQueue.main.async {
                    self.lastFallbackReason = "Gemini unavailable (\(reasonString)) → SmolLM2 fallback"
                    self.isCurrentlyFallback = true
                }
                return try await smolLM2Provider.generateResponse(prompt: prompt, history: history)
            }
        }
    }
    
    // MARK: - Streaming Response Execution
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        switch policy {
        case .smolLM2:
            return smolLM2Provider.streamResponse(prompt: prompt, history: history)
        case .gemini:
            return geminiProvider.streamResponse(prompt: prompt, history: history)
        case .auto:
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await chunk in self.geminiProvider.streamResponse(prompt: prompt, history: history) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch let err as AIProviderError {
                        if case .cancelled = err {
                            continuation.finish(throwing: err)
                            return
                        }
                        
                        let reasonString = err.localizedDescription
                        self.logger.warning("Gemini stream error [\(reasonString)] → Falling back to SmolLM2 stream.")
                        DispatchQueue.main.async {
                            self.lastFallbackReason = "Gemini unavailable (\(reasonString)) → SmolLM2 fallback"
                            self.isCurrentlyFallback = true
                        }
                        
                        do {
                            for try await chunk in self.smolLM2Provider.streamResponse(prompt: prompt, history: history) {
                                continuation.yield(chunk)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
    
    public func cancel() {
        geminiProvider.cancel()
        smolLM2Provider.cancel()
    }
}
