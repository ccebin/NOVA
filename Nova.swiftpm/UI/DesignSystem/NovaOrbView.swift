import SwiftUI

public struct NovaOrbView: View {
    public let state: NovaOrbState
    public let size: CGFloat
    public let audioLevel: CGFloat
    
    @State private var rotationAngle: Double = 0
    @State private var breatheScale: CGFloat = 1.0
    @State private var innerGlowOpacity: Double = 0.6
    
    public init(state: NovaOrbState = .idle, size: CGFloat = 120, audioLevel: CGFloat = 0.0) {
        self.state = state
        self.size = size
        self.audioLevel = audioLevel
    }
    
    public var body: some View {
        ZStack {
            // Layer 0: Ambient Backlight Blur
            Circle()
                .fill(ambientGradient)
                .frame(width: size * 1.35, height: size * 1.35)
                .blur(radius: size * 0.28)
                .opacity(ambientOpacity)
                .scaleEffect(breatheScale + (state == .listening || state == .responding ? audioLevel * 0.22 : 0))
            
            // Layer 1: Core Gradient Sphere
            Circle()
                .fill(coreGradient)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: shadowColor, radius: size * 0.2, x: 0, y: size * 0.05)
            
            // Layer 2: Rotating Energy Ring
            Circle()
                .fill(angularEnergyGradient)
                .frame(width: size * 0.88, height: size * 0.88)
                .rotationEffect(.degrees(rotationAngle))
                .blendMode(.screen)
                .opacity(innerGlowOpacity)
            
            // Layer 3: Central Specular Sheen
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(state == .responding ? 0.85 : 0.45),
                            Color.white.opacity(0.15),
                            Color.clear
                        ]),
                        center: .topLeading,
                        startRadius: size * 0.05,
                        endRadius: size * 0.5
                    )
                )
                .frame(width: size * 0.94, height: size * 0.94)
                .blendMode(.plusLighter)
            
            // Layer 4: State-specific iconography or subtle nucleus
            if state == .offline {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            } else if state == .thinking {
                Circle()
                    .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                    .frame(width: size * 0.55, height: size * 0.55)
                    .rotationEffect(.degrees(-rotationAngle * 1.5))
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .onAppear {
            startAnimations()
        }
        .onChange(of: state) {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        switch state {
        case .idle:
            withAnimation(
                .easeInOut(duration: 3.2).repeatForever(autoreverses: true)
            ) {
                breatheScale = 1.04
                innerGlowOpacity = 0.55
            }
            withAnimation(
                .linear(duration: 20).repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
            
        case .listening:
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            ) {
                breatheScale = 1.08
                innerGlowOpacity = 0.85
            }
            withAnimation(
                .linear(duration: 4.5).repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
            
        case .thinking:
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                breatheScale = 1.08
                innerGlowOpacity = 0.85
            }
            withAnimation(
                .linear(duration: 3.5).repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
            
        case .responding:
            withAnimation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
            ) {
                breatheScale = 1.12
                innerGlowOpacity = 0.95
            }
            withAnimation(
                .linear(duration: 5.0).repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
            
        case .offline:
            withAnimation(
                .easeInOut(duration: 4.0).repeatForever(autoreverses: true)
            ) {
                breatheScale = 0.98
                innerGlowOpacity = 0.35
            }
            rotationAngle = 0
        }
    }
    
    // MARK: - Dynamic Gradients
    
    private var coreGradient: RadialGradient {
        switch state {
        case .idle:
            return RadialGradient(
                colors: [
                    Color(red: 0.15, green: 0.45, blue: 0.95),
                    Color(red: 0.05, green: 0.15, blue: 0.55),
                    Color(red: 0.02, green: 0.05, blue: 0.22)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        case .listening:
            return RadialGradient(
                colors: [
                    Color(red: 0.00, green: 0.75, blue: 1.00),
                    Color(red: 0.05, green: 0.35, blue: 0.90),
                    Color(red: 0.02, green: 0.08, blue: 0.35)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        case .thinking:
            return RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.25, blue: 0.95),
                    Color(red: 0.15, green: 0.45, blue: 0.95),
                    Color(red: 0.05, green: 0.05, blue: 0.30)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        case .responding:
            return RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.70, blue: 1.00),
                    Color(red: 0.20, green: 0.40, blue: 0.98),
                    Color(red: 0.05, green: 0.10, blue: 0.35)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        case .offline:
            return RadialGradient(
                colors: [
                    Color(white: 0.35),
                    Color(white: 0.20),
                    Color(white: 0.10)
                ],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
        }
    }
    
    private var angularEnergyGradient: AngularGradient {
        switch state {
        case .idle, .responding, .listening:
            return AngularGradient(
                colors: [
                    Color.cyan.opacity(0.7),
                    Color.blue.opacity(0.2),
                    Color.indigo.opacity(0.8),
                    Color.purple.opacity(0.3),
                    Color.cyan.opacity(0.7)
                ],
                center: .center
            )
        case .thinking:
            return AngularGradient(
                colors: [
                    Color.purple.opacity(0.8),
                    Color.blue.opacity(0.3),
                    Color.cyan.opacity(0.8),
                    Color.pink.opacity(0.5),
                    Color.purple.opacity(0.8)
                ],
                center: .center
            )
        case .offline:
            return AngularGradient(
                colors: [
                    Color(white: 0.4),
                    Color(white: 0.2),
                    Color(white: 0.3),
                    Color(white: 0.4)
                ],
                center: .center
            )
        }
    }
    
    private var ambientGradient: RadialGradient {
        RadialGradient(
            colors: [
                ambientColor,
                ambientColor.opacity(0.4),
                Color.clear
            ],
            center: .center,
            startRadius: size * 0.1,
            endRadius: size * 0.7
        )
    }
    
    private var ambientColor: Color {
        switch state {
        case .idle: return Color(red: 0.08, green: 0.35, blue: 0.95)
        case .listening: return Color(red: 0.00, green: 0.70, blue: 1.00)
        case .thinking: return Color(red: 0.30, green: 0.20, blue: 0.95)
        case .responding: return Color(red: 0.10, green: 0.65, blue: 1.00)
        case .offline: return Color(white: 0.30)
        }
    }
    
    private var ambientOpacity: Double {
        switch state {
        case .idle: return 0.55
        case .listening: return 0.75 + Double(audioLevel * 0.20)
        case .thinking: return 0.75
        case .responding: return 0.85
        case .offline: return 0.25
        }
    }
    
    private var shadowColor: Color {
        ambientColor.opacity(0.45)
    }
}
