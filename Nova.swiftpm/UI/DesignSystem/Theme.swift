import SwiftUI

public enum NovaOrbState: String, Sendable, CaseIterable {
    case idle
    case listening
    case thinking
    case responding
    case offline
}

public enum NovaTheme {
    public static let canvas = Color.black
    public static let surface = Color(red: 0.07, green: 0.07, blue: 0.09)
    public static let surfaceCard = Color(red: 0.11, green: 0.11, blue: 0.14)
    public static let surfaceSecondaryCard = Color(red: 0.16, green: 0.16, blue: 0.20)
    public static let surfaceBorder = Color.white.opacity(0.09)
    public static let surfaceDivider = Color.white.opacity(0.06)
    
    public static let accent = Color(red: 0.04, green: 0.52, blue: 1.00) // Apple Action Blue
    public static let accentSubtle = Color(red: 0.04, green: 0.52, blue: 1.00).opacity(0.18)
    public static let statusWarning = Color(red: 1.00, green: 0.62, blue: 0.04) // Apple Orange
    public static let statusGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
    
    public static let ink = Color.white
    public static let inkSecondary = Color(white: 0.65)
    public static let inkTertiary = Color(white: 0.42)
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    public var borderOpacity: Double = 0.08

    public func body(content: Content) -> some View {
        content
            .background(NovaTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: 1)
            )
    }
}

public extension View {
    func novaGlassCard(cornerRadius: CGFloat = 16, borderOpacity: Double = 0.08) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
    }
}
