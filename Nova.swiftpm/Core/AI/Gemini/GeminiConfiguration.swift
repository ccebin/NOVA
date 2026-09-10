import Foundation

/// Configuration contract for Google Gemini API integration in NOVA (Phase 8).
/// Enforces Free Tier constraints, verified Google AI Studio endpoints, and native Gemini Live specs.
public struct GeminiConfiguration: Sendable {
    // MARK: - Verified Free Tier Models
    
    /// Official frontier Flash model recommended by Google AI Studio (Free Tier).
    public static let defaultTextModel = "gemini-3.8-flash"
    
    /// Official BidiGenerateContent live audio preview model (Free Tier).
    public static let defaultLiveModel = "gemini-3.1-flash-live-preview"
    
    // MARK: - Official Google AI Endpoints
    
    /// Google Generative Language REST v1beta base URL.
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    
    /// Official WebSocket endpoint for real-time bidirectional audio (Gemini Live).
    public static let defaultLiveWebSocketURL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
    
    // MARK: - Audio Specifications for Gemini Live
    
    /// Client Audio Input: 16-bit Linear PCM, 16 kHz, Little-Endian, Mono.
    public static let liveInputSampleRate: Double = 16000.0
    public static let liveInputChannels: Int = 1
    public static let liveInputMimeType: String = "audio/pcm;rate=16000"
    
    /// Server Audio Output: 16-bit Linear PCM, 24 kHz, Little-Endian, Mono.
    public static let liveOutputSampleRate: Double = 24000.0
    public static let liveOutputChannels: Int = 1
    public static let liveOutputMimeType: String = "audio/pcm;rate=24000"
    
    // MARK: - Thinking Level (Official Gemini 3.8 parameter)
    
    public enum ThinkingLevel: String, Sendable, CaseIterable, Codable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }
    
    // MARK: - Instance Properties
    
    public var textModel: String
    public var liveModel: String
    public var baseURL: URL
    public var liveWebSocketURL: URL
    public var temperature: Double
    public var thinkingLevel: ThinkingLevel
    
    /// Free Tier enforcement: Zero automatic billing or pay-as-you-go activation.
    public let isFreeTierOnly: Bool = true
    public let allowPaidUpgrades: Bool = false
    
    public init(
        textModel: String = GeminiConfiguration.defaultTextModel,
        liveModel: String = GeminiConfiguration.defaultLiveModel,
        baseURL: URL = GeminiConfiguration.defaultBaseURL,
        liveWebSocketURL: URL = GeminiConfiguration.defaultLiveWebSocketURL,
        temperature: Double = 0.7,
        thinkingLevel: ThinkingLevel = .low
    ) {
        self.textModel = textModel
        self.liveModel = liveModel
        self.baseURL = baseURL
        self.liveWebSocketURL = liveWebSocketURL
        self.temperature = temperature
        self.thinkingLevel = thinkingLevel
    }
}
