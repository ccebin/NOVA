import SwiftUI
import UIKit

public struct ChatInputBar: View {
    @Binding public var text: String
    public let isGenerating: Bool
    public let voiceState: NovaVoiceState
    public let onSend: () -> Void
    public let onCancel: () -> Void
    public let onVoiceToggle: () -> Void
    
    public init(
        text: Binding<String>,
        isGenerating: Bool,
        voiceState: NovaVoiceState = .idle,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void = {},
        onVoiceToggle: @escaping () -> Void = {}
    ) {
        self._text = text
        self.isGenerating = isGenerating
        self.voiceState = voiceState
        self.onSend = onSend
        self.onCancel = onCancel
        self.onVoiceToggle = onVoiceToggle
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Input Pill
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundColor(NovaTheme.inkTertiary)
                    .font(.system(size: 14))
                
                TextField("Ask NOVA...", text: $text, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(NovaTheme.ink)
                    .lineLimit(1...4)
                    .disabled(isGenerating)
                    .submitLabel(.send)
                    .onSubmit {
                        triggerSend()
                    }
                
                if !text.isEmpty && !isGenerating {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(NovaTheme.inkTertiary)
                            .font(.system(size: 15))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NovaTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NovaTheme.surfaceBorder, lineWidth: 1)
            )
            
            // Action Button: Send or Cancel
            if isGenerating {
                Button(action: triggerCancel) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            } else if canSend {
                Button(action: triggerSend) {
                    ZStack {
                        Circle()
                            .fill(NovaTheme.accent)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                // Voice Button (Push-to-Talk / Active Voice Control)
                Button(action: triggerVoiceToggle) {
                    ZStack {
                        Circle()
                            .fill(voiceButtonBackground)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(voiceButtonBorder, lineWidth: 1)
                            )
                        
                        Image(systemName: voiceButtonIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(voiceButtonForeground)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            NovaTheme.surface
                .overlay(
                    Rectangle()
                        .fill(NovaTheme.surfaceDivider)
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func triggerSend() {
        guard canSend && !isGenerating else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onSend()
    }
    
    private func triggerCancel() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        onCancel()
    }
    
    private func triggerVoiceToggle() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        onVoiceToggle()
    }
    
    private var voiceButtonBackground: Color {
        switch voiceState {
        case .listening:
            return Color(red: 0.05, green: 0.70, blue: 1.00)
        case .speaking:
            return Color.red.opacity(0.85)
        case .processing:
            return Color(red: 0.60, green: 0.45, blue: 0.95)
        case .interrupted:
            return NovaTheme.statusWarning
        case .unavailable, .error:
            return NovaTheme.surfaceCard
        case .idle:
            return NovaTheme.surfaceCard
        }
    }
    
    private var voiceButtonBorder: Color {
        switch voiceState {
        case .listening:
            return Color.white.opacity(0.4)
        case .speaking:
            return Color.white.opacity(0.3)
        case .processing:
            return Color.white.opacity(0.3)
        case .interrupted:
            return NovaTheme.statusWarning.opacity(0.5)
        case .unavailable, .error:
            return Color.red.opacity(0.4)
        case .idle:
            return NovaTheme.surfaceBorder
        }
    }
    
    private var voiceButtonIcon: String {
        switch voiceState {
        case .listening:
            return "stop.fill"
        case .speaking:
            return "stop.fill"
        case .processing:
            return "waveform.badge.magnifyingglass"
        case .interrupted:
            return "hand.raised.fill"
        case .unavailable, .error:
            return "mic.slash"
        case .idle:
            return "mic.fill"
        }
    }
    
    private var voiceButtonForeground: Color {
        switch voiceState {
        case .listening, .speaking, .processing:
            return .white
        case .interrupted:
            return .white
        case .unavailable, .error:
            return NovaTheme.statusWarning
        case .idle:
            return NovaTheme.inkSecondary
        }
    }
}
