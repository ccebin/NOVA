import SwiftUI

/// Elegant, minimal state indicator pill displaying current voice engine status
/// and real-time partial speech recognition transcripts.
public struct VoiceStateIndicator: View {
    public let state: NovaVoiceState
    public let partialTranscript: String
    public let error: NovaVoiceError?
    
    public init(
        state: NovaVoiceState,
        partialTranscript: String = "",
        error: NovaVoiceError? = nil
    ) {
        self.state = state
        self.partialTranscript = partialTranscript
        self.error = error
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Pill status badge
            HStack(spacing: 6) {
                Image(systemName: state.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                
                Text(stateTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(badgeBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusColor.opacity(0.3), lineWidth: 1)
            )
            
            // Partial Transcript Display (UI state only, real-time feedback)
            if !partialTranscript.isEmpty && (state == .listening || state == .processing) {
                Text("\"\(partialTranscript)\"")
                    .font(.system(size: 14, weight: .regular))
                    .italic()
                    .foregroundColor(NovaTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let err = error, (state == .error || state == .unavailable) {
                Text(err.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.statusWarning)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: partialTranscript)
    }
    
    private var stateTitle: String {
        switch state {
        case .idle:
            return "Voice Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing Voice..."
        case .speaking:
            return "NOVA Speaking"
        case .interrupted:
            return "Interrupted, Listening..."
        case .unavailable:
            return "Offline Voice Unavailable"
        case .error:
            return "Voice Error"
        }
    }
    
    private var statusColor: Color {
        switch state {
        case .listening:
            return Color(red: 0.05, green: 0.70, blue: 1.00)
        case .speaking:
            return Color(red: 0.20, green: 0.85, blue: 0.95)
        case .processing:
            return Color(red: 0.60, green: 0.45, blue: 0.95)
        case .interrupted:
            return NovaTheme.statusWarning
        case .unavailable, .error:
            return Color.red.opacity(0.85)
        case .idle:
            return NovaTheme.inkTertiary
        }
    }
    
    private var badgeBackground: Color {
        statusColor.opacity(0.12)
    }
}
