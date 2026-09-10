import Foundation
import SwiftData

/// The primary unified intelligence provider for NOVA.
/// Coordinates ConversationContext, ContextBuilder, MemoryManager, AdaptiveReasoningEngine,
/// and ToolRegistry without domain-specific hardcoding.
public struct NovaConversationalDecisionProvider: AgentDecisionProvider, @unchecked Sendable {
    public let provider: any AIProvider
    public let personality: NovaPersonality
    public let memoryManager: MemoryManager
    
    public init(
        provider: any AIProvider,
        personality: NovaPersonality = .shared,
        memoryManager: MemoryManager = .shared
    ) {
        self.provider = provider
        self.personality = personality
        self.memoryManager = memoryManager
    }
    
    public func decideNextStep(
        prompt: String,
        history: [ChatMessage],
        availableTools: [ToolDefinition],
        previousToolResults: [ToolResult]
    ) async throws -> AgentTurn {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Post-Tool Execution Verification Gate Feedback
        if !previousToolResults.isEmpty {
            let lastResult = previousToolResults.last!
            if lastResult.status == .success && (lastResult.verification?.isVerified ?? false) {
                return .directResponse("✓ \(lastResult.toolName) successfully verified on your iPhone: \(lastResult.verification?.explanation ?? lastResult.message)")
            } else {
                return .directResponse("Notice: \(lastResult.toolName) could not be verified on your iPhone. Details: \(lastResult.message)")
            }
        }
        
        // 2. Conservative Explicit Memory Extraction
        let memoryExtraction = memoryManager.shouldExtractMemory(from: trimmed)
        if memoryExtraction.shouldSave, let key = memoryExtraction.key, let content = memoryExtraction.content {
            let saved = memoryManager.saveOrUpdateMemory(
                key: key,
                content: content,
                category: memoryExtraction.category,
                importance: 4,
                confidence: memoryExtraction.confidence,
                source: .explicitUser,
                reasonForRetention: "Explicit user command"
            )
            return .directResponse("Noted. I'll remember that \(saved.content).")
        }
        
        // 3. Context & Memory Construction
        let relevantMemories = memoryManager.retrieveRelevantMemories(for: trimmed, limit: 3)
        let context = ConversationContext(
            currentMessage: trimmed,
            recentTurns: history,
            relevantMemories: relevantMemories,
            previousToolResults: previousToolResults
        )
        
        // 4. Adaptive Reasoning Mode Classification
        let reasoningMode = AdaptiveReasoningEngine.shared.classify(
            prompt: trimmed,
            context: context,
            availableTools: availableTools
        )
        
        // 5. Tool Action Path (ONLY taken when reasoning mode is .tool)
        if reasoningMode == .tool {
            if let matched = GenericToolRouter.matchAndExtract(prompt: trimmed, from: ToolRegistry.shared) {
                return .toolCall(ToolCallRequest(
                    toolId: matched.tool.definition.id,
                    arguments: matched.arguments.storage
                ))
            }
        }
        
        // 6. Conversational / Direct / Complex Dialogue Path (NO tools called!)
        let assembled = ContextBuilder.shared.buildContext(
            currentMessage: trimmed,
            context: context,
            personality: personality,
            reasoningMode: reasoningMode,
            availableTools: availableTools
        )
        
        let response = try await provider.generateResponse(
            prompt: assembled.fullPromptForModel,
            history: assembled.formattedHistory
        )
        return .directResponse(response)
    }
}
