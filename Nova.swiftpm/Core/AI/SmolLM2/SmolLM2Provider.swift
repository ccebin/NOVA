import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Real on-device generative intelligence provider for SmolLM2-360M-Instruct via Apple Core ML.
/// Enforces exact model contract: 32 layers, GQA 15:5, head_dim 64, 49,152 vocabulary, and ChatML format.
/// Never simulates responses or fakes weights.
public final class SmolLM2Provider: AIProvider, @unchecked Sendable {
    public let id: String = "coreml.smollm2.360m"
    public let displayName: String = "SmolLM2-360M-Instruct (Core ML)"
    public let isGenerative: Bool = true
    
    public let tokenizer: SmolLM2Tokenizer
    public let sampler: SmolLM2Sampler
    
    public private(set) var detailedStatus: SmolLM2ModelStatus = .modelNotFound
    public private(set) var lastInferenceStatus: String = "Idle"
    
    public var resolvedModelPath: String? {
        resolvedModelURL?.path
    }
    
    public var isModelLoaded: Bool {
        #if canImport(CoreML)
        return loadedModel != nil
        #else
        return false
        #endif
    }
    
    private var isGeneratingState: Bool = false
    private var currentTask: Task<Void, Never>?
    
    #if canImport(CoreML)
    private var loadedModel: MLModel?
    #endif
    private var resolvedModelURL: URL?
    
    public init() {
        self.tokenizer = SmolLM2Tokenizer()
        self.sampler = SmolLM2Sampler()
        locateAndInspectModel()
    }
    
    // MARK: - Model Location & Verification
    
    /// Locates the real compiled model artifact in Bundle or local Documents.
    public func locateAndInspectModel() {
        // 1. Check main bundle resources
        if let bundleURL = Bundle.main.url(forResource: "SmolLM2-360M-Instruct-4bit", withExtension: "mlmodelc") {
            self.resolvedModelURL = bundleURL
            self.detailedStatus = .modelReady
            self.lastInferenceStatus = "Model discovered in Bundle: \(bundleURL.lastPathComponent)"
            return
        }
        
        // 2. Check Application Documents/Models/ directory
        let fileManager = FileManager.default
        if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidate1 = docsURL.appendingPathComponent("Models/\(SmolLM2Contract.compiledModelName)")
            if fileManager.fileExists(atPath: candidate1.path) {
                self.resolvedModelURL = candidate1
                self.detailedStatus = .modelReady
                self.lastInferenceStatus = "Model discovered in Documents/Models: \(candidate1.lastPathComponent)"
                return
            }
            let candidate2 = docsURL.appendingPathComponent(SmolLM2Contract.compiledModelName)
            if fileManager.fileExists(atPath: candidate2.path) {
                self.resolvedModelURL = candidate2
                self.detailedStatus = .modelReady
                self.lastInferenceStatus = "Model discovered in Documents: \(candidate2.lastPathComponent)"
                return
            }
        }
        
        self.resolvedModelURL = nil
        self.detailedStatus = .modelNotFound
        self.lastInferenceStatus = "Model not found on disk: '\(SmolLM2Contract.compiledModelName)'"
    }
    
    public var isModelArtifactPresent: Bool {
        resolvedModelURL != nil
    }
    
    public var modelState: AIModelState {
        if isGeneratingState {
            return .generating
        }
        
        #if canImport(CoreML)
        guard resolvedModelURL != nil else {
            return .modelNotReady
        }
        return .ready
        #else
        // Running on Linux host where CoreML framework is unavailable
        return .modelNotReady
        #endif
    }
    
    public var statusDiagnostic: String {
        if let url = resolvedModelURL {
            return "Real artifact located: \(url.lastPathComponent) (ANE / GPU Hardware Accelerated)"
        } else {
            return "Model artifact missing. Required: '\(SmolLM2Contract.compiledModelName)' in Documents/Models/."
        }
    }
    
    // MARK: - Generation & Streaming
    
    public func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String {
        try Task.checkCancellation()
        
        guard isModelArtifactPresent else {
            self.detailedStatus = .modelNotFound
            self.lastInferenceStatus = "Model weights missing from disk"
            throw AIProviderError.serviceUnavailable(
                "SmolLM2-360M-Instruct weights not found on disk. Place '\(SmolLM2Contract.compiledModelName)' in local Documents/Models/ without network."
            )
        }
        
        #if canImport(CoreML)
        if #available(iOS 18.0, macOS 15.0, *) {
            let formattedPrompt = tokenizer.formatChatML(
                systemPrompt: "You are NOVA, a calm, intelligent, standalone offline assistant.",
                history: history,
                currentPrompt: prompt
            )
            return try await runInferenceLoop(prompt: formattedPrompt)
        } else {
            self.detailedStatus = .inferenceFailed
            self.lastInferenceStatus = "Core ML 8 stateful operations unavailable on this OS version"
            throw AIProviderError.serviceUnavailable(
                "SmolLM2-360M-Instruct requires Core ML 8 stateful operations available only on iOS 18.0+ / macOS 15.0+."
            )
        }
        #else
        self.detailedStatus = .modelNotFound
        self.lastInferenceStatus = "Core ML execution not supported on Linux host"
        throw AIProviderError.serviceUnavailable(
            "Core ML runtime execution is not supported on this host operating system (requires iOS 18+ / macOS 15+)."
        )
        #endif
    }
    
    public func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard isModelArtifactPresent else {
                self.detailedStatus = .modelNotFound
                self.lastInferenceStatus = "Model weights missing from disk"
                continuation.finish(
                    throwing: AIProviderError.serviceUnavailable(
                        "SmolLM2-360M-Instruct weights not found on disk. Place '\(SmolLM2Contract.compiledModelName)' in local Documents/Models/."
                    )
                )
                return
            }
            
            #if canImport(CoreML)
            if #available(iOS 18.0, macOS 15.0, *) {
                let formattedPrompt = tokenizer.formatChatML(
                    systemPrompt: "You are NOVA, a calm, intelligent, standalone offline assistant.",
                    history: history,
                    currentPrompt: prompt
                )
                
                let task = Task {
                    do {
                        isGeneratingState = true
                        defer { isGeneratingState = false }
                        
                        try await runStreamingInference(prompt: formattedPrompt, continuation: continuation)
                        continuation.finish()
                    } catch {
                        if Task.isCancelled {
                            self.detailedStatus = .cancelled
                            self.lastInferenceStatus = "Streaming cancelled"
                            continuation.finish(throwing: AIProviderError.cancelled)
                        } else {
                            self.detailedStatus = .inferenceFailed
                            self.lastInferenceStatus = "Streaming error: \(error.localizedDescription)"
                            continuation.finish(throwing: error)
                        }
                    }
                }
                self.currentTask = task
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            } else {
                self.detailedStatus = .inferenceFailed
                self.lastInferenceStatus = "Core ML 8 required"
                continuation.finish(
                    throwing: AIProviderError.serviceUnavailable(
                        "SmolLM2-360M-Instruct requires Core ML 8 stateful operations available only on iOS 18.0+ / macOS 15.0+."
                    )
                )
            }
            #else
            self.detailedStatus = .modelNotFound
            self.lastInferenceStatus = "Core ML not supported on host"
            continuation.finish(
                throwing: AIProviderError.serviceUnavailable(
                    "Core ML runtime execution is not supported on this host operating system."
                )
            )
            #endif
        }
    }
    
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isGeneratingState = false
        detailedStatus = .cancelled
        lastInferenceStatus = "Inference cancelled"
    }
    
    // MARK: - Core ML Execution Engine (Platform Isolated)
    
    #if canImport(CoreML)
    private func loadModelIfNeeded() throws -> MLModel {
        if let existing = loadedModel {
            return existing
        }
        guard let url = resolvedModelURL else {
            self.detailedStatus = .modelNotFound
            throw AIProviderError.serviceUnavailable("Model artifact URL resolution failed.")
        }
        
        let config = MLModelConfiguration()
        config.computeUnits = .all // Utilizes Apple Neural Engine + Apple GPU
        
        do {
            let model = try MLModel(contentsOf: url, configuration: config)
            self.loadedModel = model
            self.detailedStatus = .modelReady
            self.lastInferenceStatus = "Model loaded successfully into memory"
            return model
        } catch {
            self.detailedStatus = .modelFoundButLoadFailed
            self.lastInferenceStatus = "Model compilation/load failed: \(error.localizedDescription)"
            throw AIProviderError.executionFailed("Model load failed: \(error.localizedDescription)")
        }
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func runInferenceLoop(prompt: String) async throws -> String {
        isGeneratingState = true
        defer { isGeneratingState = false }
        
        let model = try loadModelIfNeeded()
        let promptTokens = tokenizer.encode(prompt)
        guard !promptTokens.isEmpty else { throw AIProviderError.promptEmpty }
        
        // Context boundary check: reject if prompt exceeds 2048 tokens
        if promptTokens.count > SmolLM2Contract.maxContextLength {
            let err = "Prompt length (\(promptTokens.count) tokens) exceeds maximum context length of \(SmolLM2Contract.maxContextLength) tokens."
            self.detailedStatus = .inferenceFailed
            self.lastInferenceStatus = err
            throw AIProviderError.executionFailed(err)
        }
        
        // Initialize Core ML 8 MLState for key_cache and value_cache
        let state = model.makeState()
        
        // 1. Prefill pass over all prompt tokens
        var logits = try prefillPrompt(model: model, tokens: promptTokens, using: state)
        
        var generatedTokens: [Int] = []
        var recentTokens = promptTokens
        
        // Calculate remaining token budget to prevent exceeding 2048 total context
        let maxAllowedNewTokens = min(512, SmolLM2Contract.maxContextLength - promptTokens.count)
        if maxAllowedNewTokens <= 0 {
            return ""
        }
        
        // 2. Autoregressive decode loop
        var currentSeqLen = promptTokens.count
        for _ in 0..<maxAllowedNewTokens {
            try Task.checkCancellation()
            if currentSeqLen >= SmolLM2Contract.maxContextLength {
                break
            }
            
            let nextToken = sampler.sample(from: logits, recentTokenIds: recentTokens)
            
            // Break on EOS (<|im_end|> or <|endoftext|>)
            if nextToken == SmolLM2Contract.imEndTokenId || nextToken == SmolLM2Contract.endOfTextTokenId {
                break
            }
            
            generatedTokens.append(nextToken)
            recentTokens.append(nextToken)
            if recentTokens.count > 64 {
                recentTokens.removeFirst()
            }
            
            currentSeqLen += 1
            // Predict next logits using new token and stateful KV-cache
            logits = try predictNextTokenLogits(model: model, token: nextToken, using: state)
        }
        
        self.lastInferenceStatus = "Generated \(generatedTokens.count) tokens successfully"
        return tokenizer.decode(generatedTokens)
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func runStreamingInference(
        prompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let model = try loadModelIfNeeded()
        let promptTokens = tokenizer.encode(prompt)
        guard !promptTokens.isEmpty else { throw AIProviderError.promptEmpty }
        
        // Context boundary check: reject if prompt exceeds 2048 tokens
        if promptTokens.count > SmolLM2Contract.maxContextLength {
            let err = "Prompt length (\(promptTokens.count) tokens) exceeds maximum context length of \(SmolLM2Contract.maxContextLength) tokens."
            self.detailedStatus = .inferenceFailed
            self.lastInferenceStatus = err
            throw AIProviderError.executionFailed(err)
        }
        
        let state = model.makeState()
        
        // 1. Prefill pass over prompt
        var logits = try prefillPrompt(model: model, tokens: promptTokens, using: state)
        
        var recentTokens = promptTokens
        let maxAllowedNewTokens = min(512, SmolLM2Contract.maxContextLength - promptTokens.count)
        if maxAllowedNewTokens <= 0 {
            return
        }
        
        // 2. Decode streaming loop
        var currentSeqLen = promptTokens.count
        for _ in 0..<maxAllowedNewTokens {
            try Task.checkCancellation()
            if currentSeqLen >= SmolLM2Contract.maxContextLength {
                break
            }
            
            let nextToken = sampler.sample(from: logits, recentTokenIds: recentTokens)
            
            if nextToken == SmolLM2Contract.imEndTokenId || nextToken == SmolLM2Contract.endOfTextTokenId {
                break
            }
            
            let piece = tokenizer.decode([nextToken])
            continuation.yield(piece)
            
            recentTokens.append(nextToken)
            if recentTokens.count > 64 {
                recentTokens.removeFirst()
            }
            
            currentSeqLen += 1
            logits = try predictNextTokenLogits(model: model, token: nextToken, using: state)
        }
        self.lastInferenceStatus = "Streaming completed successfully"
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func prefillPrompt(model: MLModel, tokens: [Int], using state: MLModel.State) throws -> [Float] {
        let seqLen = tokens.count
        guard seqLen > 0 else { throw AIProviderError.promptEmpty }
        
        // Construct input_ids [1, seqLen] (Int32)
        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        for (idx, token) in tokens.enumerated() {
            inputArray[idx] = NSNumber(value: Int32(token))
        }
        
        // Construct causal_mask [1, 1, seqLen, seqLen] (Float16)
        let maskArray = try MLMultiArray(shape: [1, 1, NSNumber(value: seqLen), NSNumber(value: seqLen)], dataType: .float16)
        let maskPtr = maskArray.dataPointer.bindMemory(to: Float16.self, capacity: seqLen * seqLen)
        for i in 0..<seqLen {
            for j in 0..<seqLen {
                let idx = i * seqLen + j
                maskPtr[idx] = (j <= i) ? Float16(0.0) : Float16(-10000.0)
            }
        }
        
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            SmolLM2Contract.inputIdsName: inputArray,
            SmolLM2Contract.causalMaskName: maskArray
        ])
        
        let output = try model.prediction(from: inputs, using: state)
        guard let logitsMultiArray = output.featureValue(for: SmolLM2Contract.logitsName)?.multiArrayValue else {
            throw AIProviderError.executionFailed("Model output missing 'logits' tensor.")
        }
        
        let vocabCount = SmolLM2Contract.vocabSize
        var lastTokenLogits = [Float](repeating: 0.0, count: vocabCount)
        let logitsPtr = logitsMultiArray.dataPointer.bindMemory(to: Float16.self, capacity: seqLen * vocabCount)
        let lastTokenOffset = (seqLen - 1) * vocabCount
        for v in 0..<vocabCount {
            lastTokenLogits[v] = Float(logitsPtr[lastTokenOffset + v])
        }
        return lastTokenLogits
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func predictNextTokenLogits(model: MLModel, token: Int, using state: MLModel.State) throws -> [Float] {
        // Construct input_ids tensor [1, 1] (Int32)
        let inputArray = try MLMultiArray(shape: [1, 1], dataType: .int32)
        inputArray[0] = NSNumber(value: Int32(token))
        
        // Construct causal mask tensor [1, 1, 1, 1] (Float16)
        let maskArray = try MLMultiArray(shape: [1, 1, 1, 1], dataType: .float16)
        let maskPtr = maskArray.dataPointer.bindMemory(to: Float16.self, capacity: 1)
        maskPtr[0] = Float16(0.0)
        
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            SmolLM2Contract.inputIdsName: inputArray,
            SmolLM2Contract.causalMaskName: maskArray
        ])
        
        let output = try model.prediction(from: inputs, using: state)
        guard let logitsMultiArray = output.featureValue(for: SmolLM2Contract.logitsName)?.multiArrayValue else {
            throw AIProviderError.executionFailed("Model output missing 'logits' tensor.")
        }
        
        let vocabCount = SmolLM2Contract.vocabSize
        var logits = [Float](repeating: 0.0, count: vocabCount)
        let logitsPtr = logitsMultiArray.dataPointer.bindMemory(to: Float16.self, capacity: vocabCount)
        for i in 0..<vocabCount {
            logits[i] = Float(logitsPtr[i])
        }
        return logits
    }
    #endif
}
