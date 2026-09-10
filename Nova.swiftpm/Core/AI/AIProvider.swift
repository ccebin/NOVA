import Foundation

public struct ChatMessage: Sendable, Identifiable {
    public let id: UUID
    public let role: MessageRoleEnum
    public let content: String
    public let timestamp: Date
    
    public init(id: UUID = UUID(), role: MessageRoleEnum, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum AIModelState: String, Sendable, Equatable {
    case ready = "Model Ready"
    case generating = "Generating..."
    case deviceNotEligible = "Device Ineligible"
    case modelNotReady = "Model Not Ready / Downloading"
    case appleIntelligenceDisabled = "Apple Intelligence Disabled"
    case sdkUnavailable = "FoundationModels SDK Unavailable in this Build"
    case unavailable = "Model Unavailable"
}

public enum AIProviderError: LocalizedError, Sendable, Equatable {
    case serviceUnavailable(String)
    case executionFailed(String)
    case promptEmpty
    case cancelled
    case quotaExceeded(String)
    case networkUnavailable(String)
    case authenticationFailed(String)
    case rateLimited(String)
    case modelNotReady(String)
    
    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable(let reason):
            return "AI Provider Unavailable: \(reason)"
        case .executionFailed(let reason):
            return "AI Execution Failed: \(reason)"
        case .promptEmpty:
            return "Prompt cannot be empty."
        case .cancelled:
            return "Generation was cancelled by the user."
        case .quotaExceeded(let reason):
            return "Quota Exceeded (Free Tier Limit): \(reason)"
        case .networkUnavailable(let reason):
            return "Network Unavailable: \(reason)"
        case .authenticationFailed(let reason):
            return "Authentication Failed: \(reason)"
        case .rateLimited(let reason):
            return "Rate Limited: \(reason)"
        case .modelNotReady(let reason):
            return "Model Not Ready: \(reason)"
        }
    }
}

public protocol AIProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var isGenerative: Bool { get }
    var modelState: AIModelState { get }
    
    func generateResponse(
        prompt: String,
        history: [ChatMessage]
    ) async throws -> String
    
    func streamResponse(
        prompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error>
    
    func cancel()
}
