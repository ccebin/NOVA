import Foundation

public enum ReasoningMode: String, Codable, Sendable {
    case direct = "Direct"
    case conversational = "Conversational"
    case tool = "Tool"
    case complex = "Complex"
}

/// Dynamic reasoning mode classifier that evaluates structured intent signals,
/// conversational context, and registered tool definitions.
public struct AdaptiveReasoningEngine: Sendable {
    public static let shared = AdaptiveReasoningEngine()
    
    public init() {}
    
    /// Classifies the appropriate reasoning depth using contextual interpretation.
    /// Never relies solely on naive isolated word matching.
    public func classify(
        prompt: String,
        context: ConversationContext,
        availableTools: [ToolDefinition] = []
    ) -> ReasoningMode {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // 1. Contextual Anaphora & Follow-up Actions
        // E.g., "Set one for tomorrow." depends on prior turn topic
        if isContextualActionFollowUp(lower: lower, recentTurns: context.recentTurns) {
            return .tool
        }
        
        // 2. Direct Factual / Computational Queries
        if isDirectComputationOrFact(lower: lower) {
            return .direct
        }
        
        // 3. Complex Analytical / Multi-dimensional Queries
        if isComplexAnalytical(lower: lower) {
            return .complex
        }
        
        // 4. Action / Tool Execution Queries
        if isActionIntent(lower: lower, prompt: trimmed, availableTools: availableTools) {
            return .tool
        }
        
        // 5. Default to natural conversational dialogue
        return .conversational
    }
    
    /// Instructions injected into context to calibrate model depth
    public func depthGuidance(for mode: ReasoningMode) -> String {
        switch mode {
        case .direct:
            return "Provide a concise, direct, and factually exact answer without conversational preamble or unnecessary explanation."
        case .conversational:
            return "Engage naturally with NOVA's calm and witty personality. Maintain conversational rhythm. Do not trigger tools."
        case .tool:
            return "The user requires an on-device action. Structure parameters accurately according to the registered tool definitions."
        case .complex:
            return "Provide structured, multi-dimensional reasoning, trade-off analysis, and substantive intellectual depth."
        }
    }
    
    // MARK: - Classification Helpers
    
    private func isContextualActionFollowUp(lower: String, recentTurns: [ChatMessage]) -> Bool {
        let followUpPatterns = ["set one ", "create one", "add one", "schedule one", "remind me then", "make one"]
        let hasPattern = followUpPatterns.contains { lower.hasPrefix($0) || lower.contains($0) }
        
        guard hasPattern else { return false }
        
        // Look at previous turns to see if reminder/event was the context
        if let lastTurn = recentTurns.last?.content.lowercased() {
            if lastTurn.contains("reminder") || lastTurn.contains("calendar") || lastTurn.contains("event") || lastTurn.contains("call") {
                return true
            }
        }
        return false
    }
    
    private func isDirectComputationOrFact(lower: String) -> Bool {
        // Simple arithmetic check: e.g. "25 * 4", "100 / 5", "12 + 15"
        let mathOperators: Set<Character> = ["+", "-", "*", "/", "%", "^"]
        let hasMath = lower.contains(where: { mathOperators.contains($0) }) && lower.contains(where: { $0.isNumber })
        if hasMath && lower.count < 30 {
            return true
        }
        
        // Brief definition or status check
        if lower.hasPrefix("what is ") && lower.count < 25 {
            return true
        }
        if lower == "status" || lower == "ping" || lower == "time" {
            return true
        }
        return false
    }
    
    private func isComplexAnalytical(lower: String) -> Bool {
        let complexMarkers = [
            "explain whether",
            "is realistically possible",
            "compare ",
            "trade-offs",
            "tradeoffs",
            "architecture",
            "philosophical",
            "in-depth",
            "how would you design",
            "pros and cons",
            "deep dive",
            "analyze",
            "underlying reasons"
        ]
        return complexMarkers.contains { lower.contains($0) }
    }
    
    private func isActionIntent(lower: String, prompt: String, availableTools: [ToolDefinition]) -> Bool {
        // Explicit tool trigger syntax
        if lower.hasPrefix("tool:") || lower.hasPrefix("/tool") {
            return true
        }
        
        // Check against registered tool definitions
        for toolDef in availableTools {
            let nameWords = toolDef.name.lowercased().components(separatedBy: .whitespaces)
            let matchesAll = nameWords.allSatisfy { lower.contains($0) }
            if matchesAll {
                return true
            }
        }
        
        // Check action verbs with date/time intent
        let actionVerbs = ["remind me to ", "schedule a meeting", "schedule an event", "create a reminder"]
        return actionVerbs.contains { lower.contains($0) }
    }
}
