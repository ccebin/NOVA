import SwiftUI
import SwiftData

/// Dedicated voice interaction panel displaying live waveform, partial transcripts,
/// and interactive push-to-talk controls.
public struct VoiceInputView: View {
    @ObservedObject public var voiceManager: NovaVoiceManager
    public let appState: AppState
    public let modelContext: ModelContext
    
    public init(
        voiceManager: NovaVoiceManager = .shared,
        appState: AppState,
        modelContext: ModelContext
    ) {
        self.voiceManager = voiceManager
        self.appState = appState
        self.modelContext = modelContext
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header: State Indicator & Live Partial Transcript
            VoiceStateIndicator(
                state: voiceManager.state,
                partialTranscript: voiceManager.partialTranscript,
                error: voiceManager.lastError
            )
            
            // Audio Waveform (Driven by real microphone RMS amplitude or TTS)
            VoiceWaveformView(
                audioLevel: voiceManager.audioLevel,
                state: voiceManager.state,
                barCount: 9,
                maxHeight: 26
            )
            .padding(.vertical, 2)
            
            // Controls row
            HStack(spacing: 20) {
                // Cancel / Dismiss button
                Button(action: {
                    voiceManager.cancel()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(NovaTheme.inkSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(NovaTheme.surfaceCard)
                    .clipShape(Capsule())
                }
                
                // Primary Action Button (Stop & Process, or Stop Speaking)
                if voiceManager.state == .listening {
                    Button(action: {
                        voiceManager.stopListeningAndProcess(appState: appState, modelContext: modelContext)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Done Speaking")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.05, green: 0.70, blue: 1.00))
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 0.05, green: 0.70, blue: 1.00).opacity(0.4), radius: 8, x: 0, y: 2)
                    }
                } else if voiceManager.state == .speaking {
                    Button(action: {
                        voiceManager.stopSpeaking()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Stop Voice")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.85))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            NovaTheme.surfaceCard
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(NovaTheme.surfaceBorder, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
