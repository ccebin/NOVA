import Foundation
import SwiftData
import os

/// Protocol for the decision-making engine of the agent loop.
/// Can be backed by FoundationModels LanguageModelSession or deterministic drivers.
public protocol AgentDecisionProvider: Sendable {
    func decideNextStep(
        prompt: String,
        history: [ChatMessage],
        availableTools: [ToolDefinition],
        previousToolResults: [ToolResult]
    ) async throws -> AgentTurn
}

/// Generic multi-turn agent coordinator implementing:
/// USER INPUT -> DECIDE -> VALIDATE -> SAFETY -> EXECUTOR -> VERIFY -> MODEL -> FINAL RESPONSE
@MainActor
public final class AgentToolExecutionLoop: ObservableObject {
    public static let shared = AgentToolExecutionLoop()
    
    private let logger = Logger(subsystem: "com.nova.assistant", category: "AgentLoop")
    
    public init() {}
    
    public func runLoop(
        prompt: String,
        history: [ChatMessage],
        decisionProvider: any AgentDecisionProvider,
        toolRegistry: ToolRegistry = .shared,
        executor: ToolExecutor = .shared,
        modelContext: ModelContext? = nil,
        maxIterations: Int = 5,
        isUserConfirmed: Bool = true
    ) async throws -> AgentLoopResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AIProviderError.promptEmpty
        }
        
        var toolResults: [ToolResult] = []
        var currentIteration = 0
        
        while currentIteration < maxIterations {
            try Task.checkCancellation()
            currentIteration += 1
            
            logger.info("Agent loop turn \(currentIteration)/\(maxIterations)")
            
            let availableDefinitions = toolRegistry.allDefinitions()
            let nextStep = try await decisionProvider.decideNextStep(
                prompt: trimmedPrompt,
                history: history,
                availableTools: availableDefinitions,
                previousToolResults: toolResults
            )
            
            try Task.checkCancellation()
            
            switch nextStep {
            case .directResponse(let responseText):
                // Enforce Verification Gate: Response must NOT claim success if any executed tool failed verification
                let verifiedResponse = enforceVerificationGate(
                    response: responseText,
                    toolResults: toolResults
                )
                return AgentLoopResult(
                    finalResponse: verifiedResponse,
                    toolExecutions: toolResults,
                    iterationsCount: currentIteration,
                    completedSuccessfully: true
                )
                
            case .toolCall(let request):
                guard let tool = toolRegistry.tool(for: request.toolId) else {
                    let errorResult = ToolResult(
                        toolId: request.toolId,
                        toolName: request.toolId,
                        status: .notFound,
                        message: "Requested tool '\(request.toolId)' not found in ToolRegistry."
                    )
                    toolResults.append(errorResult)
                    continue
                }
                
                let toolArgs = ToolArguments(request.arguments)
                
                // 1. Argument Schema Validation: Never execute if arguments are invalid
                let validationErrors = toolArgs.validate(against: tool.definition.arguments)
                if !validationErrors.isEmpty {
                    let errorMsg = "Invalid arguments: \(validationErrors.joined(separator: ", "))"
                    logger.error("\(errorMsg)")
                    let invalidResult = ToolResult(
                        toolId: tool.definition.id,
                        toolName: tool.definition.name,
                        status: .invalidArguments,
                        message: errorMsg
                    )
                    toolResults.append(invalidResult)
                    continue
                }
                
                // 2. Safety Gate: Block prohibited or unconfirmed high-risk operations
                if tool.definition.riskLevel == .highRiskDestructive && !isUserConfirmed {
                    let cancelMsg = "High-risk action cancelled: explicit user confirmation required."
                    logger.warning("\(cancelMsg)")
                    let cancelledResult = ToolResult(
                        toolId: tool.definition.id,
                        toolName: tool.definition.name,
                        status: .cancelled,
                        message: cancelMsg
                    )
                    toolResults.append(cancelledResult)
                    continue
                }
                
                // 3. ToolExecutor: Permission -> Before State -> Action -> Observation -> After State -> Diff -> Verify -> SwiftData
                let context = ToolExecutionContext(
                    idempotencyKey: UUID().uuidString,
                    isUserConfirmed: isUserConfirmed
                )
                
                let executionResult = await executor.execute(
                    tool: tool,
                    arguments: toolArgs,
                    context: context,
                    modelContext: modelContext
                )
                
                toolResults.append(executionResult)
                // Continue loop to feed execution result back to the decision provider
                
            case .error(let errorMsg):
                logger.error("Agent decision error: \(errorMsg)")
                return AgentLoopResult(
                    finalResponse: "Agent error: \(errorMsg)",
                    toolExecutions: toolResults,
                    iterationsCount: currentIteration,
                    completedSuccessfully: false
                )
            }
        }
        
        // Loop hit max iteration cap
        let limitMsg = "Agent loop stopped: maximum iteration limit (\(maxIterations)) reached."
        logger.warning("\(limitMsg)")
        return AgentLoopResult(
            finalResponse: limitMsg,
            toolExecutions: toolResults,
            iterationsCount: currentIteration,
            completedSuccessfully: false
        )
    }
    
    /// Verification Gate: Asserts that an assistant message never claims success if any tool action failed verification
    private func enforceVerificationGate(response: String, toolResults: [ToolResult]) -> String {
        guard !toolResults.isEmpty else { return response }
        
        var failureExplanations: [String] = []
        for result in toolResults {
            let passed = (result.status == .success && (result.verification?.isVerified ?? false))
            if !passed {
                failureExplanations.append("\(result.toolName): \(result.message)")
            }
        }
        
        if !failureExplanations.isEmpty {
            let lower = response.lowercased()
            let optimisticWords = ["done", "created", "scheduled", "success", "added", "reminded"]
            let isOverlyOptimistic = optimisticWords.contains { lower.contains($0) }
            
            if isOverlyOptimistic {
                return "Notice: The requested action could not be verified on your device. Details: \(failureExplanations.joined(separator: "; "))"
            }
        }
        
        return response
    }
}

/// Default agent decision provider that combines the active AI provider with generic schema matching
public struct StandardAgentDecisionProvider: AgentDecisionProvider, @unchecked Sendable {
    public let provider: any AIProvider
    
    public init(provider: any AIProvider) {
        self.provider = provider
    }
    
    public func decideNextStep(
        prompt: String,
        history: [ChatMessage],
        availableTools: [ToolDefinition],
        previousToolResults: [ToolResult]
    ) async throws -> AgentTurn {
        // If tools have already executed in this loop, summarize results
        if !previousToolResults.isEmpty {
            let lastResult = previousToolResults.last!
            if lastResult.status == .success && (lastResult.verification?.isVerified ?? false) {
                return .directResponse("✓ \(lastResult.toolName) successfully verified on iPhone: \(lastResult.verification?.explanation ?? lastResult.message)")
            } else {
                return .directResponse("Notice: \(lastResult.toolName) could not be verified on your device (\(lastResult.message)).")
            }
        }
        
        // Match against registered tool definitions dynamically
        if let matched = GenericToolRouter.matchAndExtract(prompt: prompt, from: ToolRegistry.shared) {
            return .toolCall(ToolCallRequest(
                toolId: matched.tool.definition.id,
                arguments: matched.arguments.storage
            ))
        }
        
        // Direct response from active AI provider
        let response = try await provider.generateResponse(prompt: prompt, history: history)
        return .directResponse(response)
    }
}
