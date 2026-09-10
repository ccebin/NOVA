import Foundation

public struct AssembledModelContext: Sendable {
    public let systemPrompt: String
    public let formattedHistory: [ChatMessage]
    public let currentMessage: String
    public let activeTopic: String?
    public let reasoningMode: ReasoningMode
    public let relevantMemories: [MemoryEntity]
    public let fullPromptForModel: String
}

/// Assembles unified context for model prompts using strict priority:
/// 1. Current user message
/// 2. Current conversation context (active topic, recent turns)
/// 3. Explicit current-session instructions
/// 4. Relevant persistent memories (never overriding current input)
/// 5. NOVA personality
/// 6. General tool capabilities
public struct ContextBuilder: Sendable {
    public static let shared = ContextBuilder()
    
    public init() {}
    
    public func buildContext(
        currentMessage: String,
        context: ConversationContext,
        personality: NovaPersonality = .shared,
        reasoningMode: ReasoningMode,
        availableTools: [ToolDefinition] = []
    ) -> AssembledModelContext {
        // Priority 5: NOVA Personality foundation
        var systemSections: [String] = []
        systemSections.append(personality.systemInstruction())
        
        // Priority 3: Explicit reasoning depth instruction
        systemSections.append("### REASONING DEPTH DIRECTIVE\nMode: \(reasoningMode.rawValue)\n\(AdaptiveReasoningEngine.shared.depthGuidance(for: reasoningMode))")
        
        // Priority 4: Relevant Persistent Memories (With explicit rule that current input overrides memory)
        if !context.relevantMemories.isEmpty {
            var memoryText = "### RELEVANT LONG-TERM MEMORIES (Context only — Current user input ALWAYS overrides memory):\n"
            for mem in context.relevantMemories {
                memoryText += "• [\(mem.category.rawValue)] \(mem.content)\n"
            }
            systemSections.append(memoryText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // Priority 6: General Tool Capabilities (When relevant)
        if reasoningMode == .tool || reasoningMode == .complex {
            if !availableTools.isEmpty {
                var toolSection = "### AVAILABLE ON-DEVICE TOOLS\n"
                for tool in availableTools {
                    toolSection += "• \(tool.name) (\(tool.id)): \(tool.description)\n"
                }
                systemSections.append(toolSection.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        let systemPrompt = systemSections.joined(separator: "\n\n")
        
        // Priority 2: Conversation Context (Recent windowed turns)
        let windowedHistory = Array(context.recentTurns.suffix(8))
        
        // Priority 1: Current User Message & Full Assembled Prompt
        var promptParts: [String] = []
        promptParts.append(systemPrompt)
        
        if let topic = context.activeTopic {
            promptParts.append("### ACTIVE TOPIC ANCHOR\n\(topic)")
        }
        
        if !windowedHistory.isEmpty {
            var historyText = "### RECENT CONVERSATION TURNS\n"
            for turn in windowedHistory {
                let speaker = turn.role == .user ? "User" : personality.assistantName
                historyText += "\(speaker): \(turn.content)\n"
            }
            promptParts.append(historyText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        promptParts.append("### CURRENT USER INPUT\nUser: \(currentMessage)\n\(personality.assistantName):")
        
        let fullPrompt = promptParts.joined(separator: "\n\n")
        
        return AssembledModelContext(
            systemPrompt: systemPrompt,
            formattedHistory: windowedHistory,
            currentMessage: currentMessage,
            activeTopic: context.activeTopic,
            reasoningMode: reasoningMode,
            relevantMemories: context.relevantMemories,
            fullPromptForModel: fullPrompt
        )
    }
}
