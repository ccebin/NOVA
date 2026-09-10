import SwiftUI
import SwiftData
import Combine

public enum ActiveEngineSelection: String, CaseIterable, Identifiable, Sendable {
    case autoRouter = "auto_router"
    case geminiFlash = "gemini_flash"
    case smolLM2CoreML = "smollm2_coreml"
    case foundationModels = "foundation_models"
    case degradedFallback = "degraded_fallback"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .autoRouter:
            return "Auto: Gemini Flash (SmolLM2 Fallback)"
        case .geminiFlash:
            return "Gemini 3.8 Flash (Cloud Only — Free Tier)"
        case .smolLM2CoreML:
            return "SmolLM2-360M-Instruct (Core ML)"
        case .foundationModels:
            return "Apple Foundation Models (iOS 26+ SDK)"
        case .degradedFallback:
            return "Degraded Offline Fallback"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @AppStorage("nova_assistant_name") public var assistantName: String = "NOVA"
    
    @Published public var activeConversation: ConversationEntity?
    @Published public var messages: [MessageEntity] = []
    @Published public var orbState: NovaOrbState = .idle
    @Published public var isGenerating: Bool = false
    @Published public var streamingBubbleText: String = ""
    @Published public var capabilitiesReport: SystemCapabilitiesReport
    @Published public var activeProviderId: String = ""
    @Published public var activeProviderName: String = ""
    @Published public var modelState: AIModelState = .ready
    @Published public var statusBannerDismissed: Bool = false
    @Published public var fallbackNotice: String? = nil
    
    public let voiceManager = NovaVoiceManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    @Published public var selectedEngine: ActiveEngineSelection = .autoRouter
    @Published public var voicePolicy: VoiceRoutingPolicy = .localVoice
    
    public let geminiKeyProvider: CompositeGeminiKeyProvider
    public let geminiProvider: GeminiProvider
    public let geminiLiveProvider: GeminiLiveProvider
    public let smolLM2Provider: SmolLM2Provider
    public let foundationModelsProvider: FoundationModelsProvider
    public let degradedFallbackProvider: DegradedFallbackProvider
    public let inferenceRouter: InferenceEngineRouter
    
    private var activeProvider: any AIProvider
    private var dataManager: LocalDataManager?
    private var isBootstrapped: Bool = false
    
    public init() {
        let detector = CapabilityDetector.shared
        let report = detector.detectCapabilities()
        self.capabilitiesReport = report
        
        let keyProvider = CompositeGeminiKeyProvider()
        let gemini = GeminiProvider(keyProvider: keyProvider)
        let smol = SmolLM2Provider()
        let live = GeminiLiveProvider(keyProvider: keyProvider)
        let foundation = FoundationModelsProvider()
        let degraded = DegradedFallbackProvider()
        
        let router = InferenceEngineRouter(
            geminiProvider: gemini,
            smolLM2Provider: smol,
            geminiLiveProvider: live,
            initialPolicy: .auto,
            initialVoicePolicy: .localVoice
        )
        
        self.geminiKeyProvider = keyProvider
        self.geminiProvider = gemini
        self.geminiLiveProvider = live
        self.smolLM2Provider = smol
        self.foundationModelsProvider = foundation
        self.degradedFallbackProvider = degraded
        self.inferenceRouter = router
        
        // Default engine: Auto Router (Gemini 3.8 Flash with SmolLM2 Core ML fallback)
        self.activeProvider = router
        self.activeProviderId = router.id
        self.activeProviderName = router.displayName
        self.modelState = router.modelState
        self.orbState = .idle
        
        // Observe fallback notifications from InferenceEngineRouter
        router.$lastFallbackReason
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reason in
                self?.fallbackNotice = reason
            }
            .store(in: &cancellables)
        
        // Synchronize Orb visual state with real Voice state
        voiceManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] voiceState in
                guard let self = self else { return }
                switch voiceState {
                case .listening, .interrupted:
                    self.orbState = .listening
                case .processing:
                    self.orbState = .thinking
                case .speaking:
                    self.orbState = .responding
                case .error, .unavailable:
                    self.orbState = .offline
                case .idle:
                    if !self.isGenerating {
                        self.orbState = .idle
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    public func bootstrap(modelContext: ModelContext) {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        
        let dm = LocalDataManager(modelContext: modelContext)
        self.dataManager = dm
        
        let conv = dm.getOrCreateActiveConversation()
        self.activeConversation = conv
        self.messages = dm.fetchMessages(for: conv)
    }
    
    public func refreshCapabilities() {
        let report = CapabilityDetector.shared.detectCapabilities()
        self.capabilitiesReport = report
        selectEngine(self.selectedEngine)
    }
    
    /// Switches the active intelligence engine according to user preference.
    public func selectEngine(_ engine: ActiveEngineSelection) {
        self.selectedEngine = engine
        switch engine {
        case .autoRouter:
            inferenceRouter.policy = .auto
            self.activeProvider = inferenceRouter
            self.activeProviderId = inferenceRouter.id
            self.activeProviderName = inferenceRouter.displayName
            self.modelState = inferenceRouter.modelState
        case .geminiFlash:
            inferenceRouter.policy = .gemini
            self.activeProvider = inferenceRouter
            self.activeProviderId = geminiProvider.id
            self.activeProviderName = geminiProvider.displayName
            self.modelState = geminiProvider.modelState
        case .smolLM2CoreML:
            inferenceRouter.policy = .smolLM2
            smolLM2Provider.locateAndInspectModel()
            self.activeProvider = smolLM2Provider
            self.activeProviderId = smolLM2Provider.id
            self.activeProviderName = smolLM2Provider.displayName
            self.modelState = smolLM2Provider.modelState
        case .foundationModels:
            self.activeProvider = foundationModelsProvider
            self.activeProviderId = foundationModelsProvider.id
            self.activeProviderName = foundationModelsProvider.displayName
            self.modelState = foundationModelsProvider.modelState
        case .degradedFallback:
            self.activeProvider = degradedFallbackProvider
            self.activeProviderId = degradedFallbackProvider.id
            self.activeProviderName = degradedFallbackProvider.displayName
            self.modelState = degradedFallbackProvider.modelState
        }
    }
    
    public func selectVoicePolicy(_ policy: VoiceRoutingPolicy) {
        self.voicePolicy = policy
        inferenceRouter.voicePolicy = policy
    }
    
    public func sendMessage(_ text: String, modelContext: ModelContext) {
        Task {
            try? await sendConversationMessage(text, modelContext: modelContext)
        }
    }
    
    @discardableResult
    public func sendConversationMessage(_ text: String, modelContext: ModelContext) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return "" }
        
        if dataManager == nil {
            dataManager = LocalDataManager(modelContext: modelContext)
        }
        guard let dm = dataManager else { return "" }
        
        if activeConversation == nil {
            activeConversation = dm.getOrCreateActiveConversation()
        }
        guard let conv = activeConversation else { return "" }
        
        // 1. Persist User Message
        let userMsg = dm.addMessage(role: .user, content: trimmed, to: conv)
        self.messages.append(userMsg)
        
        self.isGenerating = true
        self.modelState = .generating
        self.orbState = .thinking
        self.streamingBubbleText = ""
        
        // 2. Unified Conversational Intelligence Loop (Context, Memory, Personality, Adaptive Reasoning, Tools)
        let history: [ChatMessage] = self.messages.map {
            ChatMessage(id: $0.id, role: $0.role, content: $0.content, timestamp: $0.timestamp)
        }
        
        let decisionProvider = NovaConversationalDecisionProvider(
            provider: self.activeProvider,
            personality: NovaPersonality(assistantName: self.assistantName),
            memoryManager: MemoryManager.shared
        )
        
        do {
            self.orbState = .thinking
            let loopResult = try await AgentToolExecutionLoop.shared.runLoop(
                prompt: trimmed,
                history: history,
                decisionProvider: decisionProvider,
                modelContext: modelContext
            )
            
            let lastTool = loopResult.toolExecutions.last
            let assistantMsg = dm.addMessage(
                role: .assistant,
                content: loopResult.finalResponse,
                to: conv,
                toolName: lastTool?.toolName,
                toolStatus: lastTool?.status,
                toolVerificationPassed: lastTool?.verification?.isVerified ?? (lastTool?.status == .success),
                toolExplanation: lastTool?.verification?.explanation ?? lastTool?.message,
                toolDiffSummary: lastTool?.diff?.summary
            )
            self.messages.append(assistantMsg)
            self.isGenerating = false
            self.modelState = self.activeProvider.modelState
            self.orbState = (lastTool == nil || lastTool?.status == .success) ? .idle : .offline
            if lastTool != nil && lastTool?.status != .success {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.orbState = .idle
            }
            return loopResult.finalResponse
        } catch {
            if let aiErr = error as? AIProviderError, case .cancelled = aiErr {
                self.isGenerating = false
                self.modelState = self.activeProvider.modelState
                self.orbState = .idle
                throw error
            }
            
            let fallbackContent: String
            if let aiErr = error as? AIProviderError {
                fallbackContent = "Notice: \(aiErr.localizedDescription)"
            } else {
                fallbackContent = "Notice: \(error.localizedDescription)"
            }
            
            let assistantMsg = dm.addMessage(role: .assistant, content: fallbackContent, to: conv)
            self.messages.append(assistantMsg)
            self.isGenerating = false
            self.modelState = self.activeProvider.modelState
            self.orbState = .offline
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.orbState = .idle
            return fallbackContent
        }
    }
    
    public func cancelCurrentGeneration() {
        activeProvider.cancel()
        isGenerating = false
        streamingBubbleText = ""
        modelState = activeProvider.modelState
        orbState = .idle
    }
    
    public func clearConversation(modelContext: ModelContext) {
        if dataManager == nil {
            dataManager = LocalDataManager(modelContext: modelContext)
        }
        guard let dm = dataManager else { return }
        
        if let conv = activeConversation {
            let all = dm.fetchAllConversations()
            for c in all where c.id == conv.id {
                modelContext.delete(c)
            }
            try? modelContext.save()
        }
        
        self.activeConversation = dm.getOrCreateActiveConversation()
        self.messages = []
        self.streamingBubbleText = ""
        self.isGenerating = false
        self.modelState = self.activeProvider.modelState
        self.orbState = .idle
    }
}
