import Foundation

/// A structured tool call requested by a language model or agent coordinator.
public struct ToolCallRequest: Sendable, Identifiable {
    public let id: String
    public let toolId: String
    public let arguments: [String: String]
    
    public init(id: String = UUID().uuidString, toolId: String, arguments: [String: String]) {
        self.id = id
        self.toolId = toolId
        self.arguments = arguments
    }
}

/// A discrete step or decision produced during the agent loop.
public enum AgentTurn: Sendable {
    case directResponse(String)
    case toolCall(ToolCallRequest)
    case error(String)
}

/// The final outcome of the multi-turn agent loop.
public struct AgentLoopResult: Sendable {
    public let finalResponse: String
    public let toolExecutions: [ToolResult]
    public let iterationsCount: Int
    public let completedSuccessfully: Bool
    
    public init(
        finalResponse: String,
        toolExecutions: [ToolResult] = [],
        iterationsCount: Int = 1,
        completedSuccessfully: Bool = true
    ) {
        self.finalResponse = finalResponse
        self.toolExecutions = toolExecutions
        self.iterationsCount = iterationsCount
        self.completedSuccessfully = completedSuccessfully
    }
}
