import Foundation
import Speech
import AVFoundation

/// Offline-first on-device speech recognizer utilizing AVAudioEngine and Apple's Speech framework.
/// Enforces requiresOnDeviceRecognition = true to guarantee zero cloud network usage.
public final class NovaSpeechRecognizer: NSObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var currentLocale: Locale
    private var isRecording: Bool = false
    
    // Callbacks
    public var onPartialTranscript: (@Sendable (_ text: String) -> Void)?
    public var onFinalTranscript: (@Sendable (_ text: String) -> Void)?
    public var onAudioLevel: (@Sendable (_ level: Float) -> Void)?
    public var onError: (@Sendable (_ error: NovaVoiceError) -> Void)?
    
    public init(locale: Locale = Locale.current) {
        self.currentLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }
    
    // MARK: - Configuration & Locales
    
    public func updateLocale(_ locale: Locale) {
        self.currentLocale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    public var activeLocale: Locale {
        currentLocale
    }
    
    // MARK: - Capabilities & Permissions
    
    public func speechPermissionStatus() -> VoicePermissionStatus {
        #if os(iOS)
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
        #else
        return .granted
        #endif
    }
    
    public func requestSpeechPermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        #else
        return true
        #endif
    }
    
    public var isSpeechAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    public var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }
    
    // MARK: - Recognition Lifecycle
    
    public func startListening() throws {
        guard !isRecording else { return }
        
        // 1. Permission check
        let permission = speechPermissionStatus()
        guard permission == .granted else {
            throw NovaVoiceError.speechPermissionDenied
        }
        
        // 2. Hardware / Service availability check
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NovaVoiceError.speechRecognitionUnavailable
        }
        
        // 3. Strict Offline Capability Check
        // SFSpeechRecognizer must support on-device recognition for this locale
        guard recognizer.supportsOnDeviceRecognition else {
            throw NovaVoiceError.offlineSpeechUnavailable(locale: currentLocale.identifier)
        }
        
        // 4. Teardown any previous stale tasks
        teardownAudioEngine()
        
        // 5. Activate Audio Session
        try NovaAudioSession.shared.activate()
        
        // 6. Setup Audio Engine & Recognition Request
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        // HARD CONSTRAINT: strictly require on-device recognition, never connect to Apple cloud
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Ensure format is valid
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            teardownAudioEngine()
            throw NovaVoiceError.microphoneUnavailable
        }
        
        // 7. Install tap for live audio buffer and amplitude calculation
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Forward PCM buffer to Speech Recognizer
            self.recognitionRequest?.append(buffer)
            
            // Calculate genuine RMS amplitude (0.0 to 1.0)
            let level = Self.calculateAudioLevel(from: buffer)
            self.onAudioLevel?(level)
        }
        
        // 8. Start Audio Engine
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            teardownAudioEngine()
            throw NovaVoiceError.audioSessionFailed(reason: error.localizedDescription)
        }
        
        // 9. Start Recognition Task
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                
                if result.isFinal {
                    self.onFinalTranscript?(transcript)
                } else {
                    self.onPartialTranscript?(transcript)
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                // Ignore standard cancellation codes (e.g. 216 is cancellation)
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 1110) {
                    return
                }
                if nsError.domain == "kLSRErrorDomain" && nsError.code == 201 {
                    return
                }
                
                // If on-device assets are missing or recognizer failed
                if nsError.localizedDescription.contains("on-device") || nsError.code == 1700 {
                    self.onError?(.offlineSpeechUnavailable(locale: self.currentLocale.identifier))
                } else {
                    self.onError?(.recognitionFailed(reason: error.localizedDescription))
                }
            }
        }
    }
    
    public func stopListening() {
        guard isRecording else { return }
        
        // Signal end of audio to request
        recognitionRequest?.endAudio()
        
        // Cleanly stop engine and remove tap
        teardownAudioEngine()
        isRecording = false
        
        // Reset audio level
        onAudioLevel?(0.0)
    }
    
    public func cancel() {
        isRecording = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        teardownAudioEngine()
        onAudioLevel?(0.0)
    }
    
    private func teardownAudioEngine() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    // MARK: - Audio Amplitude Metering
    
    /// Computes Root Mean Square (RMS) power from audio buffer and normalizes between 0.0 and 1.0.
    private static func calculateAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        
        var sum: Float = 0.0
        let stride = max(1, frameLength / 64) // sample subset for high-performance metering
        var count: Float = 0.0
        
        for i in stride(from: 0, to: frameLength, by: stride) {
            let sample = channelData[i]
            sum += sample * sample
            count += 1.0
        }
        
        guard count > 0 else { return 0.0 }
        let rms = sqrt(sum / count)
        
        // Map RMS (typical range 0.001 to 0.4) logarithmically to 0.0 ... 1.0
        let minDb: Float = -60.0
        let db = 20.0 * log10(max(rms, 0.00001))
        let normalized = max(0.0, min(1.0, (db - minDb) / (0.0 - minDb)))
        return normalized
    }
}
