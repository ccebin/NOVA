import Foundation

/// Represents the active conversational frame, maintaining topic continuity,
/// pronoun anchors, windowed turns, and relevant memories.
public struct ConversationContext: Sendable {
    public let currentMessage: String
    public let recentTurns: [ChatMessage]
    public let activeTopic: String?
    public let relevantMemories: [MemoryEntity]
    public let previousToolResults: [ToolResult]
    public let currentNovaState: String
    
    public init(
        currentMessage: String,
        recentTurns: [ChatMessage],
        activeTopic: String? = nil,
        relevantMemories: [MemoryEntity] = [],
        previousToolResults: [ToolResult] = [],
        currentNovaState: String = "Online"
    ) {
        self.currentMessage = currentMessage
        self.recentTurns = recentTurns
        self.activeTopic = activeTopic ?? ConversationContext.inferActiveTopic(from: recentTurns, current: currentMessage)
        self.relevantMemories = relevantMemories
        self.previousToolResults = previousToolResults
        self.currentNovaState = currentNovaState
    }
    
    /// Detects active topic and resolves anaphoric references ("it", "this", "that", "the architecture")
    /// across multi-turn exchanges.
    public static func inferActiveTopic(from history: [ChatMessage], current: String) -> String? {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        let anaphora = ["it", "this", "that", "the project", "the app", "the architecture", "the assistant", "one"]
        let hasAnaphora = anaphora.contains { word in
            lower.contains(" \(word) ") || lower.hasPrefix("\(word) ") || lower.hasSuffix(" \(word)") || lower == word
        }
        
        // If current message relies on anaphora, find the dominant topic from the last user or assistant turn
        if hasAnaphora || history.count > 0 {
            for msg in history.reversed() {
                let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.count > 10 && !content.hasPrefix("✓") && !content.hasPrefix("Notice:") {
                    // Extract first conceptual phrase (up to 48 characters)
                    let firstSentence = content.components(separatedBy: CharacterSet(charactersIn: ".?!")).first ?? content
                    let preview = String(firstSentence.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !preview.isEmpty {
                        return preview
                    }
                }
            }
        }
        
        return nil
    }
}
