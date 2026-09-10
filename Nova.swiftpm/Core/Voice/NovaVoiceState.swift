import Foundation

/// Real state machine states for NOVA Native Voice Subsystem.
/// Reflects genuine underlying audio, recognition, intelligence, and speech operations.
public enum NovaVoiceState: String, Sendable, CaseIterable {
    /// Inactive, waiting for explicit user interaction.
    case idle
    
    /// Microphone and audio engine active; transcribing user speech.
    case listening
    
    /// User finished speaking; transcript being processed by existing NOVA intelligence loop.
    case processing
    
    /// NOVA is speaking the verified final response through AVSpeechSynthesizer.
    case speaking
    
    /// NOVA speech interrupted (barge-in); synthesizer stopped, transitioning to new listening.
    case interrupted
    
    /// Voice hardware, offline model, or permissions are unavailable.
    case unavailable
    
    /// An operational error occurred during capture, recognition, or playback.
    case error
    
    public var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .speaking:
            return "Speaking"
        case .interrupted:
            return "Interrupted"
        case .unavailable:
            return "Unavailable"
        case .error:
            return "Error"
        }
    }
    
    public var userFacingPrompt: String {
        switch self {
        case .idle:
            return "Tap microphone to speak"
        case .listening:
            return "Listening to your voice..."
        case .processing:
            return "Thinking..."
        case .speaking:
            return "NOVA is speaking..."
        case .interrupted:
            return "Interrupted, listening..."
        case .unavailable:
            return "Voice features unavailable"
        case .error:
            return "Voice error encountered"
        }
    }
    
    public var systemImageName: String {
        switch self {
        case .idle:
            return "mic"
        case .listening:
            return "mic.fill"
        case .processing:
            return "waveform.badge.magnifyingglass"
        case .speaking:
            return "speaker.wave.2.fill"
        case .interrupted:
            return "hand.raised.fill"
        case .unavailable:
            return "mic.slash"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    public var isActiveVoiceSession: Bool {
        switch self {
        case .listening, .processing, .speaking, .interrupted:
            return true
        case .idle, .unavailable, .error:
            return false
        }
    }
}
