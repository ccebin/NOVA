import SwiftUI

public struct ToolExecutionReceiptView: View {
    public let toolName: String
    public let status: ToolStatus
    public let verificationPassed: Bool
    public let explanation: String
    public let diffSummary: String?
    public let durationMs: Double
    
    public init(
        toolName: String,
        status: ToolStatus,
        verificationPassed: Bool,
        explanation: String,
        diffSummary: String? = nil,
        durationMs: Double = 0.0
    ) {
        self.toolName = toolName
        self.status = status
        self.verificationPassed = verificationPassed
        self.explanation = explanation
        self.diffSummary = diffSummary
        self.durationMs = durationMs
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Tool Name + Status Badge
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(statusColor)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(toolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Divider()
                .background(NovaTheme.surfaceDivider)
            
            // Step Pipeline Indicators
            VStack(alignment: .leading, spacing: 6) {
                stepRow(number: "1", title: "Captured Before State", isDone: true)
                stepRow(number: "2", title: "Executed Action on iPhone", isDone: status != .permissionDenied && status != .invalidArguments)
                stepRow(number: "3", title: "Observed Result via Apple API", isDone: status == .success || status == .verificationFailed)
                stepRow(number: "4", title: "Verified Expected vs Actual", isDone: status == .success || status == .verificationFailed, isVerified: verificationPassed)
            }
            
            // Diff / Summary Details
            if let diff = diffSummary, !diff.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("State Change:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NovaTheme.inkTertiary)
                    Text(diff)
                        .font(.system(size: 12))
                        .foregroundColor(NovaTheme.inkSecondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NovaTheme.surfaceSecondaryCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Explanation
            Text(explanation)
                .font(.system(size: 12))
                .foregroundColor(verificationPassed ? NovaTheme.inkSecondary : NovaTheme.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .novaGlassCard(cornerRadius: 14)
    }
    
    private var iconName: String {
        switch status {
        case .success:
            return "checkmark.seal.fill"
        case .verificationFailed:
            return "exclamationmark.triangle.fill"
        case .permissionDenied:
            return "hand.raised.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .failed, .invalidArguments, .notFound:
            return "xmark.octagon.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .success:
            return NovaTheme.statusGreen
        case .verificationFailed:
            return NovaTheme.statusWarning
        case .permissionDenied, .failed, .invalidArguments:
            return Color.red.opacity(0.85)
        case .cancelled, .notFound:
            return NovaTheme.inkTertiary
        }
    }
    
    private var statusText: String {
        switch status {
        case .success:
            return "Verified ✓"
        case .verificationFailed:
            return "Verification Failed"
        case .permissionDenied:
            return "Permission Denied"
        case .cancelled:
            return "Cancelled"
        case .invalidArguments:
            return "Invalid Args"
        case .failed:
            return "Failed"
        case .notFound:
            return "Not Found"
        }
    }
    
    private func stepRow(number: String, title: String, isDone: Bool, isVerified: Bool? = nil) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isDone ? (isVerified == false ? NovaTheme.statusWarning : NovaTheme.statusGreen) : NovaTheme.inkTertiary.opacity(0.3))
                .frame(width: 5, height: 5)
            
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(isDone ? NovaTheme.inkSecondary : NovaTheme.inkTertiary)
        }
    }
}
