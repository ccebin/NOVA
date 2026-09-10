import SwiftUI
import SwiftData

public struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @State private var inputText: String = ""
    @State private var showingClearConfirmation: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Status Bar
                headerView
                
                // Capability Warning Banner (if Generative AI is unavailable)
                if !appState.capabilitiesReport.isGenerativeAIAvailable && !appState.statusBannerDismissed {
                    capabilityNoticeBanner
                }
                
                // Message List or Empty State
                ScrollViewReader { proxy in
                    ScrollView {
                        if appState.messages.isEmpty {
                            emptyStateView
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(appState.messages, id: \.id) { msg in
                                    MessageBubbleView(
                                        role: msg.role,
                                        content: msg.content,
                                        timestamp: msg.timestamp,
                                        toolName: msg.toolName,
                                        toolStatus: msg.toolStatus,
                                        toolVerificationPassed: msg.toolVerificationPassed,
                                        toolExplanation: msg.toolExplanation,
                                        toolDiffSummary: msg.toolDiffSummary
                                    )
                                    .id(msg.id)
                                }
                                
                                if appState.isGenerating && !appState.streamingBubbleText.isEmpty {
                                    MessageBubbleView(
                                        role: .assistant,
                                        content: appState.streamingBubbleText,
                                        isStreaming: true
                                    )
                                    .id("streaming_bubble")
                                }
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .background(NovaTheme.canvas)
                    .onChange(of: appState.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: appState.streamingBubbleText) {
                        scrollToBottom(proxy: proxy)
                    }
                }
                
                // Active Voice Panel (HUD displayed during live voice interactions)
                if appState.voiceManager.isVoiceModeActive || appState.voiceManager.state.isActiveVoiceSession {
                    VoiceInputView(
                        voiceManager: appState.voiceManager,
                        appState: appState,
                        modelContext: modelContext
                    )
                }
                
                // Input Bar
                ChatInputBar(
                    text: $inputText,
                    isGenerating: appState.isGenerating,
                    voiceState: appState.voiceManager.state,
                    onSend: {
                        let textToSend = inputText
                        inputText = ""
                        appState.sendMessage(textToSend, modelContext: modelContext)
                    },
                    onCancel: {
                        appState.cancelCurrentGeneration()
                    },
                    onVoiceToggle: {
                        appState.voiceManager.toggleVoice(appState: appState, modelContext: modelContext)
                    }
                )
            }
            .background(NovaTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        NovaOrbView(
                            state: appState.orbState,
                            size: 24,
                            audioLevel: appState.voiceManager.audioLevel
                        )
                        Text(appState.assistantName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(NovaTheme.ink)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingClearConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(NovaTheme.inkTertiary)
                    }
                    .disabled(appState.messages.isEmpty)
                }
            }
            .confirmationDialog(
                "Clear Conversation?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Messages", role: .destructive) {
                    appState.clearConversation(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all message history from local memory.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(modelStateColor)
                    .frame(width: 7, height: 7)
                
                Text(appState.modelState.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NovaTheme.inkSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 11))
                Text("Offline")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(NovaTheme.inkTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(NovaTheme.surfaceCard)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(NovaTheme.surface)
    }
    
    private var modelStateColor: Color {
        switch appState.modelState {
        case .ready:
            return NovaTheme.statusGreen
        case .generating:
            return Color.cyan
        case .sdkUnavailable, .modelNotReady:
            return NovaTheme.statusWarning
        case .deviceNotEligible, .appleIntelligenceDisabled, .unavailable:
            return Color.red.opacity(0.8)
        }
    }
    
    private var capabilityNoticeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(NovaTheme.statusWarning)
                .font(.system(size: 15))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Generative AI Unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NovaTheme.ink)
                Text("Operating in standalone local mode. Messages and tasks are saved locally on this iPhone.")
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.inkSecondary)
            }
            
            Spacer()
            
            Button(action: { appState.statusBannerDismissed = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(NovaTheme.inkTertiary)
                    .padding(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NovaTheme.statusWarning.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(NovaTheme.statusWarning.opacity(0.25))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            
            NovaOrbView(
                state: appState.orbState,
                size: 130,
                audioLevel: appState.voiceManager.audioLevel
            )
            .padding(.top, 20)
            
            VStack(spacing: 6) {
                Text("Hello, I am \(appState.assistantName)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(NovaTheme.ink)
                
                Text(appState.capabilitiesReport.isGenerativeAIAvailable
                     ? "Your private, on-device AI assistant."
                     : "Your offline personal assistant running standalone on iPhone.")
                    .font(.system(size: 14))
                    .foregroundColor(NovaTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Suggestion Chips
            VStack(spacing: 8) {
                suggestionChip(title: "Check System Capabilities", command: "status")
                suggestionChip(title: "Show Assistant Help", command: "help")
                suggestionChip(title: "Test Offline Persistence", command: "Save a test note in memory")
            }
            .padding(.top, 12)
            
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
    }
    
    private func suggestionChip(title: String, command: String) -> some View {
        Button(action: {
            appState.sendMessage(command, modelContext: modelContext)
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .novaGlassCard(cornerRadius: 12)
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if appState.isGenerating {
                proxy.scrollTo("streaming_bubble", anchor: .bottom)
            } else if let last = appState.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
