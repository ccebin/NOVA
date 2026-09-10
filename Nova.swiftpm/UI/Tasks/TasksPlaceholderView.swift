import SwiftUI

public struct TasksPlaceholderView: View {
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(NovaTheme.accentSubtle)
                        .frame(width: 80, height: 80)
                    Image(systemName: "checklist")
                        .font(.system(size: 36))
                        .foregroundColor(NovaTheme.accent)
                }
                
                VStack(spacing: 8) {
                    Text("Autonomous Task Planner")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(NovaTheme.ink)
                    
                    Text("Phase 1 establishes the core conversational pipeline. Autonomous task decomposition, opportunistic BGTaskScheduler integration, and Live Activities will be introduced in Phase 6.")
                        .font(.system(size: 14))
                        .foregroundColor(NovaTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    featurePill(title: "Step Budgeting & ReAct Loop", icon: "arrow.triangle.2.circlepath")
                    featurePill(title: "Opportunistic BGTaskScheduler", icon: "clock.arrow.circlepath")
                    featurePill(title: "ActivityKit & Dynamic Island", icon: "platter.filled.top.iphone")
                    featurePill(title: "Action Verification Engine", icon: "checkmark.seal")
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .background(NovaTheme.canvas)
            .navigationTitle("Tasks")
        }
    }
    
    private func featurePill(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(NovaTheme.accent)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(NovaTheme.ink)
            Spacer()
            Text("Phase 6")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NovaTheme.inkTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(NovaTheme.surfaceSecondaryCard)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .novaGlassCard(cornerRadius: 12)
    }
}
