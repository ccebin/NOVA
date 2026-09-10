import Foundation
import SwiftData

// Note: FoundationModels is a future Apple Intelligence framework requiring iOS 26.0+ SDK.
// On iOS 17/18, use the fallback stub implementation below.
#if canImport(FoundationModels) && ENABLE_FOUNDATION_MODELS_PREVIEW
import FoundationModels

/// Adapter conforming to Apple's official Tool protocol in the FoundationModels framework.
/// Bridges Apple's on-device LanguageModelSession tool calls to NOVA's generic
/// ToolRegistry, ToolExecutor, before/after state capture, and SwiftData persistence.
public struct NovaFoundationModelToolAdapter: Tool, Sendable {
    public let tool: any NovaTool
    
    public init(tool: any NovaTool) {
        self.tool = tool
    }
    
    public var name: String {
        tool.definition.id
    }
    
    public var description: String {
        tool.definition.description
    }
    
    public struct Arguments: Sendable, Codable {
        public var parameters: [String: String]
        
        public init(parameters: [String: String] = [:]) {
            self.parameters = parameters
        }
    }
    
    public func call(arguments: Arguments) async throws -> String {
        let toolArgs = ToolArguments(arguments.parameters)
        let context = ToolExecutionContext(
            idempotencyKey: UUID().uuidString,
            isUserConfirmed: true
        )
        
        // Strictly routes through ToolExecutor to enforce validation, safety,
        // before-state, action, after-state, verification, and SwiftData logging.
        let result = await ToolExecutor.shared.execute(
            tool: tool,
            arguments: toolArgs,
            context: context
        )
        
        guard result.status == .success, result.verification?.isVerified == true else {
            throw ToolExecutionError.observationFailed(
                "Tool execution or verification failed: \(result.message)"
            )
        }
        
        return "Action succeeded and verified: \(result.message). Diff: \(result.diff?.summary ?? "none")"
    }
}

#else

/// Stub for environments where FoundationModels is not present in the current SDK.
/// Preserves compile safety and reports SDK limitation.
public enum FoundationModelsToolAdapterStatus {
    public static let isAvailable: Bool = false
    public static let statusDescription: String = "FoundationModels framework is not available in current SDK build (iOS 17.0 target). Requires iOS 26+ Apple Intelligence SDK."
}

#endif
