import SwiftUI

public struct MessageBubbleView: View {
    public let role: MessageRoleEnum
    public let content: String
    public let timestamp: Date
    public let isStreaming: Bool
    
    // Optional tool execution receipt data
    public let toolName: String?
    public let toolStatus: ToolStatus?
    public let toolVerificationPassed: Bool?
    public let toolExplanation: String?
    public let toolDiffSummary: String?
    
    public init(
        role: MessageRoleEnum,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolName: String? = nil,
        toolStatus: ToolStatus? = nil,
        toolVerificationPassed: Bool? = nil,
        toolExplanation: String? = nil,
        toolDiffSummary: String? = nil
    ) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolVerificationPassed = toolVerificationPassed
        self.toolExplanation = toolExplanation
        self.toolDiffSummary = toolDiffSummary
    }
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if role == .user {
                Spacer(minLength: 44)
                bubbleContent
            } else {
                bubbleContent
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    private var bubbleContent: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 6) {
            if role == .assistant {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isStreaming ? Color.cyan : Color.blue)
                        .frame(width: 6, height: 6)
                    Text("NOVA")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NovaTheme.inkSecondary)
                    
                    if isStreaming {
                        Text("verifying on iPhone...")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 2)
            }
            
            // Render Tool Execution Receipt if associated with this message
            if let tName = toolName, let tStatus = toolStatus {
                ToolExecutionReceiptView(
                    toolName: tName,
                    status: tStatus,
                    verificationPassed: toolVerificationPassed ?? (tStatus == .success),
                    explanation: toolExplanation ?? content,
                    diffSummary: toolDiffSummary
                )
                .frame(maxWidth: 340)
            } else {
                Text(content.isEmpty && isStreaming ? "..." : content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(role == .user ? .white : NovaTheme.ink)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(role == .user ? Color.white.opacity(0.15) : NovaTheme.surfaceBorder, lineWidth: 1)
                    )
            }
            
            Text(timeString)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(NovaTheme.inkTertiary)
                .padding(.horizontal, 4)
        }
    }
    
    private var bubbleBackground: some View {
        Group {
            if role == .user {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.55, blue: 1.00),
                        Color(red: 0.02, green: 0.42, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                NovaTheme.surfaceCard
            }
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
