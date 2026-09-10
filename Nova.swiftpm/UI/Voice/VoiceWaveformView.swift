import SwiftUI

/// Minimal, premium Apple-style audio waveform visualization.
/// Renders genuine audio amplitude bars driven by real microphone RMS power or TTS activity.
public struct VoiceWaveformView: View {
    public let audioLevel: CGFloat
    public let state: NovaVoiceState
    public let barCount: Int
    public let maxHeight: CGFloat
    
    public init(
        audioLevel: CGFloat,
        state: NovaVoiceState = .listening,
        barCount: Int = 7,
        maxHeight: CGFloat = 28
    ) {
        self.audioLevel = min(1.0, max(0.0, audioLevel))
        self.state = state
        self.barCount = barCount
        self.maxHeight = maxHeight
    }
    
    public var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        .spring(response: 0.18, dampingFraction: 0.55, blendDuration: 0),
                        value: audioLevel
                    )
            }
        }
        .frame(height: maxHeight)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 4.0
        
        switch state {
        case .idle:
            return minHeight
            
        case .listening:
            // Symmetrical bell-curve weighting across bars centered in the middle
            let center = CGFloat(barCount - 1) / 2.0
            let distFromCenter = abs(CGFloat(index) - center)
            let weight = max(0.2, 1.0 - (distFromCenter / center) * 0.65)
            let scaledLevel = audioLevel * weight
            let height = minHeight + (maxHeight - minHeight) * scaledLevel
            return min(maxHeight, max(minHeight, height))
            
        case .speaking:
            // Dynamic speaking cadence
            let offset = sin(Double(index) * 0.9 + Double(audioLevel * 10))
            let dynamic = minHeight + (maxHeight - minHeight) * (0.35 + 0.55 * CGFloat(offset))
            return min(maxHeight, max(minHeight, dynamic))
            
        case .processing:
            // Subtle rhythmic ripple
            let wave = sin(Double(index) * 1.2) * 0.3 + 0.4
            return minHeight + (maxHeight - minHeight) * CGFloat(wave) * 0.5
            
        case .interrupted, .unavailable, .error:
            return minHeight
        }
    }
    
    private var isCyanTone: Bool {
        state == .listening || state == .interrupted
    }
    
    private func barColor(for index: Int) -> Color {
        switch state {
        case .listening:
            return Color(red: 0.05, green: 0.70, blue: 1.00)
        case .speaking:
            return Color(red: 0.20, green: 0.85, blue: 0.95)
        case .processing:
            return Color(red: 0.60, green: 0.45, blue: 0.95)
        case .interrupted:
            return NovaTheme.statusWarning
        case .error, .unavailable:
            return Color.red.opacity(0.8)
        case .idle:
            return NovaTheme.inkTertiary
        }
    }
}
