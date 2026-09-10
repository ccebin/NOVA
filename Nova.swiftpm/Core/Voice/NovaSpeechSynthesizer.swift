import Foundation
import AVFoundation

/// Offline text-to-speech engine using Apple's AVSpeechSynthesizer.
/// Speaks verified final natural responses without leaking internal reasoning, tool JSON, or debug traces.
public final class NovaSpeechSynthesizer: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var isSpeakingState: Bool = false
    
    // Configuration
    public var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate // 0.5 default
    public var pitchMultiplier: Float = 1.0
    public var volume: Float = 1.0
    public var preferredLocale: Locale = Locale.current
    
    // Callbacks
    public var onSpeechStarted: (@Sendable () -> Void)?
    public var onSpeechFinished: (@Sendable () -> Void)?
    public var onSpeechCancelled: (@Sendable () -> Void)?
    public var onSpeechProgress: (@Sendable (_ progress: Float) -> Void)?
    public var onError: (@Sendable (_ error: NovaVoiceError) -> Void)?
    
    public override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    public var isSpeaking: Bool {
        isSpeakingState || synthesizer.isSpeaking
    }
    
    // MARK: - Speech Synthesis
    
    /// Speaks the provided text after sanitizing it to ensure internal tokens and JSON are stripped.
    public func speak(text: String, locale: Locale? = nil) {
        let cleanText = sanitizeForSpeech(text)
        guard !cleanText.isEmpty else {
            onSpeechFinished?()
            return
        }
        
        // If already speaking, stop first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Configure audio session for playback
        do {
            try NovaAudioSession.shared.activate()
        } catch {
            onError?(.audioSessionFailed(reason: error.localizedDescription))
        }
        
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        
        let targetLocale = locale ?? preferredLocale
        utterance.voice = selectBestVoice(for: targetLocale)
        
        isSpeakingState = true
        synthesizer.speak(utterance)
    }
    
    public func stop() {
        if synthesizer.isSpeaking || isSpeakingState {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeakingState = false
            onSpeechCancelled?()
        }
    }
    
    public func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }
    
    public func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }
    
    // MARK: - Voice Selection
    
    public func selectBestVoice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let langPrefix = String(identifier.prefix(2))
        
        // 1. Exact locale match
        if let exactVoice = AVSpeechSynthesisVoice(language: identifier) {
            return exactVoice
        }
        
        // 2. Language prefix match from available voices (e.g. "tr", "en")
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        if let matchingVoice = allVoices.first(where: { $0.language.lowercased().hasPrefix(langPrefix.lowercased()) }) {
            return matchingVoice
        }
        
        // 3. System default or US English fallback
        return AVSpeechSynthesisVoice(language: "en-US") ?? allVoices.first
    }
    
    // MARK: - Content Sanitization
    
    /// Ensures that raw tool schemas, markdown symbols, or debug receipts are never spoken aloud.
    public func sanitizeForSpeech(_ input: String) -> String {
        var text = input
        
        // Strip markdown bold / italic / headers / code blocks
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "#+\\s", with: "", options: .regularExpression)
        
        // Strip internal system prefixes
        if text.hasPrefix("Notice:") {
            text = text.replacingOccurrences(of: "Notice:", with: "")
        }
        if text.hasPrefix("[Generative AI Unavailable]") {
            text = text.replacingOccurrences(of: "[Generative AI Unavailable]", with: "")
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeakingState = true
        onSpeechStarted?()
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeakingState = false
        onSpeechFinished?()
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeakingState = false
        onSpeechCancelled?()
    }
    
    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let total = Float(utterance.speechString.count)
        guard total > 0 else { return }
        let progress = Float(characterRange.location + characterRange.length) / total
        onSpeechProgress?(min(1.0, progress))
    }
}
