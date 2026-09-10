import Foundation
import SwiftData

@Model
public final class ToolExecutionRecordEntity {
    @Attribute(.unique) public var id: UUID
    public var toolId: String
    public var toolName: String
    public var argumentsJSON: String
    public var startTime: Date
    public var endTime: Date
    public var durationMs: Double
    public var beforeStateJSON: String?
    public var afterStateJSON: String?
    public var diffSummary: String?
    public var verificationPassed: Bool
    public var verificationExplanation: String
    public var finalStatusRaw: String
    public var errorMessage: String?
    public var idempotencyKey: String?
    
    public var finalStatus: ToolStatus {
        get { ToolStatus(rawValue: finalStatusRaw) ?? .failed }
        set { finalStatusRaw = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        toolId: String,
        toolName: String,
        argumentsJSON: String,
        startTime: Date,
        endTime: Date,
        durationMs: Double,
        beforeStateJSON: String? = nil,
        afterStateJSON: String? = nil,
        diffSummary: String? = nil,
        verificationPassed: Bool,
        verificationExplanation: String,
        finalStatus: ToolStatus,
        errorMessage: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = durationMs
        self.beforeStateJSON = beforeStateJSON
        self.afterStateJSON = afterStateJSON
        self.diffSummary = diffSummary
        self.verificationPassed = verificationPassed
        self.verificationExplanation = verificationExplanation
        self.finalStatusRaw = finalStatus.rawValue
        self.errorMessage = errorMessage
        self.idempotencyKey = idempotencyKey
    }
}
