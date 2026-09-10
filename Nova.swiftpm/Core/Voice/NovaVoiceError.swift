import Foundation

/// Strongly-typed error model for NOVA Native Voice Subsystem.
/// Distinguishes between permissions, hardware availability, offline model readiness, and runtime lifecycle.
public enum NovaVoiceError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case speechPermissionDenied
    case speechRecognitionUnavailable
    case offlineSpeechUnavailable(locale: String)
    case recognitionFailed(reason: String)
    case audioSessionFailed(reason: String)
    case synthesisFailed(reason: String)
    case interrupted
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Please allow microphone access in Settings to use voice input."
        case .microphoneUnavailable:
            return "No microphone input hardware was detected on this device."
        case .speechPermissionDenied:
            return "Speech recognition permission was denied. Please allow speech recognition in Settings for on-device transcription."
        case .speechRecognitionUnavailable:
            return "Speech recognition service is currently unavailable on this device."
        case .offlineSpeechUnavailable(let locale):
            return "Offline speech recognition is not available for locale '\(locale)'. Apple requires on-device dictation assets to be downloaded."
        case .recognitionFailed(let reason):
            return "Speech recognition encountered an issue: \(reason)"
        case .audioSessionFailed(let reason):
            return "Audio session configuration failed: \(reason)"
        case .synthesisFailed(let reason):
            return "Speech synthesis failed: \(reason)"
        case .interrupted:
            return "Voice interaction was interrupted by another audio event or user input."
        case .cancelled:
            return "Voice interaction was cancelled."
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Open iPhone Settings > NOVA and enable Microphone."
        case .speechPermissionDenied:
            return "Open iPhone Settings > NOVA and enable Speech Recognition."
        case .offlineSpeechUnavailable:
            return "Verify on-device dictation is enabled in Settings > General > Keyboard > Dictation."
        case .microphoneUnavailable, .speechRecognitionUnavailable:
            return "Check device audio hardware or reboot device."
        case .recognitionFailed, .audioSessionFailed, .synthesisFailed:
            return "Try tapping the microphone again."
        case .interrupted, .cancelled:
            return "Ready to listen when you tap the microphone."
        }
    }
}
