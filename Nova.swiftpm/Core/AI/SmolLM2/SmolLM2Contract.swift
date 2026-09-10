import Foundation

/// Exact model specification and Core ML execution contract for SmolLM2-360M-Instruct.
/// Extracted directly from canonical Hugging Face config.json, tokenizer_config.json, and Core ML metadata.json.
public enum SmolLM2Contract {
    // Model Identity
    public static let modelIdentifier = "HuggingFaceTB/SmolLM2-360M-Instruct"
    public static let compiledModelName = "SmolLM2-360M-Instruct-4bit.mlmodelc"
    public static let packageModelName = "SmolLM2-360M-Instruct-4bit.mlpackage"
    
    // Architecture Dimensions
    public static let hiddenSize = 960
    public static let intermediateSize = 2560
    public static let numHiddenLayers = 32
    public static let numAttentionHeads = 15
    public static let numKeyValueHeads = 5 // Grouped-Query Attention (3:1 query:kv ratio)
    public static let headDimension = 64   // hiddenSize / numAttentionHeads = 960 / 15 = 64
    public static let vocabSize = 49152
    public static let maxContextLength = 2048
    
    // Exact Tokenizer Special Token IDs (Verified from tokenizer_config.json)
    public static let endOfTextTokenId = 0 // <|endoftext|>
    public static let imStartTokenId = 1   // <|im_start|>
    public static let imEndTokenId = 2     // <|im_end|>
    public static let padTokenId = 2       // <|im_end|>
    
    public static let imStartString = "<|im_start|>"
    public static let imEndString = "<|im_end|>"
    public static let endOfTextString = "<|endoftext|>"
    
    // Core ML Input Tensor Signatures (Verified from metadata.json)
    public static let inputIdsName = "input_ids"
    public static let causalMaskName = "causal_mask"
    
    // Core ML Output Tensor Signatures
    public static let logitsName = "logits"
    
    // Core ML 8 State Schema Names & Shapes
    public static let keyCacheStateName = "key_cache"
    public static let valueCacheStateName = "value_cache"
    public static let cacheStateShape: [Int] = [32, 1, 5, 2048, 64]
    
    /// Theoretical KV-cache footprint ONLY (excluding model weights, working buffers, and framework runtime).
    /// Exact calculation: 32 layers * 2 (key & value) * (1 batch * 5 heads * 2048 sequence * 64 head_dim) * 2 bytes (Float16)
    /// = 32 * 2 * 655,360 * 2 = 83,886,080 bytes (~83.88 MB).
    ///
    /// WARNING / VERIFICATION NOTE:
    /// This figure represents ONLY the theoretical memory reserved for KV tensors at full context (2048).
    /// It does NOT represent total runtime RAM. Total runtime RAM also includes:
    /// - 4-bit model weights (~203.7 MB resident when mapped)
    /// - Activation buffers and temporary compute allocations
    /// - Output logits buffer (49,152 Float16 elements)
    /// - Swift runtime and Core ML framework overhead
    /// Total runtime RAM cannot be guaranteed or assumed and MUST be measured live on a physical Apple device.
    public static let theoreticalKVCacheBytes: Int = 83_886_080 // 83.88 MB
    public static let theoreticalKVCacheMB: Double = 83.88608
    
    // Minimum Apple OS availability required by Core ML 8 stateful MLProgram
    public static let minimumIOSVersion = 18.0
    public static let minimumMacOSVersion = 15.0
}

/// Explicit model lifecycle and inference states for SmolLM2.
public enum SmolLM2ModelStatus: String, Sendable {
    case modelNotFound = "MODEL_NOT_FOUND"
    case modelFoundButLoadFailed = "MODEL_FOUND_BUT_LOAD_FAILED"
    case modelReady = "MODEL_READY"
    case inferenceFailed = "INFERENCE_FAILED"
    case cancelled = "CANCELLED"
}
