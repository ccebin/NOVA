import Foundation
import SwiftUI
import Combine
import SwiftData
import AVFoundation

/// Central coordinator for the NOVA Native Offline Voice & Conversational Audio Subsystem.
/// Bridges real microphone capture and speech recognition into the unified Phase 5 intelligence loop,
/// and directs verified final responses into AVSpeechSynthesizer.
@MainActor
public final class NovaVoiceManager: ObservableObject {
    public static let shared = NovaVoiceManager()
    
    // MARK: - Published State
    
    @Published public var state: NovaVoiceState = .idle
    @Published public var partialTranscript: String = ""
    @Published public var finalTranscript: String = ""
    @Published public var audioLevel: CGFloat = 0.0
    @Published public var lastError: NovaVoiceError? = nil
    @Published public var isVoiceModeActive: Bool = false
    @Published public var voiceLocale: Locale = Locale.current
    
    // Subsystems
    public let audioSession: NovaAudioSession
    public let recognizer: NovaSpeechRecognizer
    public let synthesizer: NovaSpeechSynthesizer
    
    // Active tasks
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        audioSession: NovaAudioSession = .shared,
        recognizer: NovaSpeechRecognizer = NovaSpeechRecognizer(),
        synthesizer: NovaSpeechSynthesizer = NovaSpeechSynthesizer()
    ) {
        self.audioSession = audioSession
        self.recognizer = recognizer
        self.synthesizer = synthesizer
        
        setupSubsystemCallbacks()
        setupLifecycleObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Subsystem Binding
    
    private func setupSubsystemCallbacks() {
        // Speech Recognizer Callbacks
        recognizer.onPartialTranscript = { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .listening else { return }
                self.partialTranscript = transcript
            }
        }
        
        recognizer.onFinalTranscript = { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.finalTranscript = transcript
                self.partialTranscript = transcript
            }
        }
        
        recognizer.onAudioLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .listening else { return }
                self.audioLevel = CGFloat(level)
            }
        }
        
        recognizer.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastError = error
                self.state = .error
                self.audioLevel = 0.0
            }
        }
        
        // Speech Synthesizer Callbacks
        synthesizer.onSpeechStarted = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state = .speaking
                self.audioLevel = 0.35
            }
        }
        
        synthesizer.onSpeechProgress = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .speaking else { return }
                // Speech activity visualization pulse
                let pulse = 0.25 + 0.35 * sin(Double(progress * 15.0))
                self.audioLevel = CGFloat(pulse)
            }
        }
        
        synthesizer.onSpeechFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.state = .idle
                self.isVoiceModeActive = false
                self.audioLevel = 0.0
                self.partialTranscript = ""
                self.finalTranscript = ""
            }
        }
        
        synthesizer.onSpeechCancelled = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = 0.0
            }
        }
        
        synthesizer.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.lastError = error
                self.state = .error
                self.audioLevel = 0.0
            }
        }
        
        // Audio Session Callbacks
        audioSession.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleAudioInterruptionBegan()
            }
        }
        
        audioSession.onRouteChange = { [weak self] reason in
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChange(reason: reason)
            }
        }
    }
    
    private func setupLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Stop voice processing immediately upon backgrounding
                if self?.state.isActiveVoiceSession == true {
                    self?.cancel()
                }
            }
        }
        #endif
    }
    
    // MARK: - User Voice Interaction Actions
    
    /// Main interaction toggle for tap-to-talk button.
    public func toggleVoice(appState: AppState, modelContext: ModelContext) {
        switch state {
        case .idle:
            startListening()
            
        case .listening:
            stopListeningAndProcess(appState: appState, modelContext: modelContext)
            
        case .speaking:
            // Interruption / Barge-in on tap
            stopSpeaking()
            
        case .processing:
            // Cancel current processing
            cancel()
            
        case .interrupted:
            startListening()
            
        case .unavailable, .error:
            resetToIdle()
        }
    }
    
    /// Begins voice capture and transcription. If NOVA is currently speaking, triggers barge-in.
    public func startListening() {
        // Handle Barge-In if speaking
        if state == .speaking {
            bargeIn()
            return
        }
        
        cancelCurrentOperations()
        
        // 1. Check Microphone Permission
        let micStatus = audioSession.microphonePermissionStatus()
        if micStatus == .denied {
            self.lastError = .microphonePermissionDenied
            self.state = .unavailable
            return
        } else if micStatus == .undetermined {
            Task {
                let granted = await self.audioSession.requestMicrophonePermission()
                if granted {
                    self.startListening()
                } else {
                    self.lastError = .microphonePermissionDenied
                    self.state = .unavailable
                }
            }
            return
        }
        
        // 2. Check Speech Recognition Permission
        let speechStatus = recognizer.speechPermissionStatus()
        if speechStatus == .denied || speechStatus == .restricted {
            self.lastError = .speechPermissionDenied
            self.state = .unavailable
            return
        } else if speechStatus == .undetermined {
            Task {
                let granted = await self.recognizer.requestSpeechPermission()
                if granted {
                    self.startListening()
                } else {
                    self.lastError = .speechPermissionDenied
                    self.state = .unavailable
                }
            }
            return
        }
        
        // 3. Check Offline Capability
        recognizer.updateLocale(voiceLocale)
        synthesizer.preferredLocale = voiceLocale
        
        guard recognizer.supportsOnDeviceRecognition else {
            self.lastError = .offlineSpeechUnavailable(locale: voiceLocale.identifier)
            self.state = .unavailable
            return
        }
        
        // 4. Start Capture
        do {
            self.partialTranscript = ""
            self.finalTranscript = ""
            self.lastError = nil
            self.isVoiceModeActive = true
            
            try recognizer.startListening()
            self.state = .listening
        } catch let error as NovaVoiceError {
            self.lastError = error
            self.state = .error
            self.isVoiceModeActive = false
        } catch {
            self.lastError = .audioSessionFailed(reason: error.localizedDescription)
            self.state = .error
            self.isVoiceModeActive = false
        }
    }
    
    /// Stops listening and immediately feeds final transcript into the unified AppState intelligence loop.
    public func stopListeningAndProcess(appState: AppState, modelContext: ModelContext) {
        guard state == .listening else { return }
        
        recognizer.stopListening()
        audioLevel = 0.0
        
        let candidateTranscript = finalTranscript.isEmpty ? partialTranscript : finalTranscript
        let trimmed = candidateTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            // No speech detected
            state = .idle
            isVoiceModeActive = false
            return
        }
        
        state = .processing
        
        processingTask = Task { [weak self, weak appState] in
            guard let self = self, let appState = appState else { return }
            
            do {
                // Route transcript directly into existing Phase 5 intelligence loop
                let response = try await appState.sendConversationMessage(trimmed, modelContext: modelContext)
                
                // If user interrupted or cancelled while processing, do not speak
                guard !Task.isCancelled, self.state == .processing else { return }
                
                self.state = .speaking
                self.synthesizer.speak(text: response, locale: self.voiceLocale)
            } catch {
                guard !Task.isCancelled else { return }
                
                let fallbackMessage = "I encountered an error processing your voice request: \(error.localizedDescription)"
                self.lastError = .recognitionFailed(reason: error.localizedDescription)
                self.state = .speaking
                self.synthesizer.speak(text: fallbackMessage, locale: self.voiceLocale)
            }
        }
    }
    
    // MARK: - Barge-in & Interruption
    
    /// Immediate barge-in: cancels current speech output and transitions into active listening.
    public func bargeIn() {
        guard state == .speaking else { return }
        
        // 1. Immediately halt synthesizer
        synthesizer.stop()
        
        // 2. Cancel pending processing task if any
        processingTask?.cancel()
        processingTask = nil
        
        // 3. Transition through .interrupted
        state = .interrupted
        audioLevel = 0.0
        partialTranscript = ""
        finalTranscript = ""
        
        // 4. Immediately begin listening for the interrupting speech
        do {
            recognizer.updateLocale(voiceLocale)
            try recognizer.startListening()
            state = .listening
            isVoiceModeActive = true
        } catch let error as NovaVoiceError {
            lastError = error
            state = .error
        } catch {
            lastError = .audioSessionFailed(reason: error.localizedDescription)
            state = .error
        }
    }
    
    public func stopSpeaking() {
        synthesizer.stop()
        state = .idle
        isVoiceModeActive = false
        audioLevel = 0.0
    }
    
    public func resetToIdle() {
        cancel()
        lastError = nil
        state = .idle
    }
    
    public func cancel() {
        cancelCurrentOperations()
        audioSession.deactivate()
        state = .idle
        isVoiceModeActive = false
        audioLevel = 0.0
        partialTranscript = ""
        finalTranscript = ""
    }
    
    private func cancelCurrentOperations() {
        processingTask?.cancel()
        processingTask = nil
        recognizer.cancel()
        synthesizer.stop()
    }
    
    // MARK: - Audio Interruptions & Route Changes
    
    private func handleAudioInterruptionBegan() {
        if state == .listening {
            recognizer.stopListening()
            state = .interrupted
        } else if state == .speaking {
            synthesizer.stop()
            state = .interrupted
        }
    }
    
    private func handleAudioRouteChange(reason: AVAudioSession.RouteChangeReason) {
        #if os(iOS)
        if reason == .oldDeviceUnavailable {
            // E.g. headphones unplugged while listening or speaking
            if state == .listening {
                recognizer.stopListening()
                state = .interrupted
            } else if state == .speaking {
                synthesizer.stop()
                state = .idle
            }
        }
        #endif
    }
}
