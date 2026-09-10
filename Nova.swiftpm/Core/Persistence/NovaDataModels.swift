import Foundation
import SwiftData

public enum MessageRoleEnum: String, Codable, Sendable {
    case user
    case assistant
    case system
}

@Model
public final class ConversationEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    public var messages: [MessageEntity]?
    
    public init(id: UUID = UUID(), title: String = "New Conversation", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = []
    }
}

@Model
public final class MessageEntity {
    @Attribute(.unique) public var id: UUID
    public var roleRaw: String
    public var content: String
    public var timestamp: Date
    public var conversation: ConversationEntity?
    
    // Optional tool execution receipt fields
    public var toolName: String?
    public var toolStatusRaw: String?
    public var toolVerificationPassed: Bool?
    public var toolExplanation: String?
    public var toolDiffSummary: String?
    
    public var role: MessageRoleEnum {
        get { MessageRoleEnum(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }
    
    public var toolStatus: ToolStatus? {
        get {
            guard let raw = toolStatusRaw else { return nil }
            return ToolStatus(rawValue: raw)
        }
        set { toolStatusRaw = newValue?.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        role: MessageRoleEnum,
        content: String,
        timestamp: Date = Date(),
        conversation: ConversationEntity? = nil,
        toolName: String? = nil,
        toolStatus: ToolStatus? = nil,
        toolVerificationPassed: Bool? = nil,
        toolExplanation: String? = nil,
        toolDiffSummary: String? = nil
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.conversation = conversation
        self.toolName = toolName
        self.toolStatusRaw = toolStatus?.rawValue
        self.toolVerificationPassed = toolVerificationPassed
        self.toolExplanation = toolExplanation
        self.toolDiffSummary = toolDiffSummary
    }
}

public enum MemoryCategory: String, Codable, Sendable, CaseIterable {
    case userPreference = "User Preference"
    case stableFact = "Stable Fact"
    case pastDecision = "Past Decision"
    case project = "Project"
    case recurringPreference = "Recurring Preference"
    case general = "General"
}

public enum MemorySource: String, Codable, Sendable {
    case explicitUser = "Explicit User Request"
    case conversationDerived = "Conversation Derived"
    case system = "System Inferred"
}

@Model
public final class MemoryEntity {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var key: String
    public var categoryRaw: String
    public var content: String
    public var importance: Int
    public var confidence: Double
    public var sourceRaw: String
    public var reasonForRetention: String
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    
    public var category: MemoryCategory {
        get { MemoryCategory(rawValue: categoryRaw) ?? .general }
        set { categoryRaw = newValue.rawValue }
    }
    
    public var source: MemorySource {
        get { MemorySource(rawValue: sourceRaw) ?? .explicitUser }
        set { sourceRaw = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        key: String,
        category: MemoryCategory = .general,
        content: String,
        importance: Int = 3,
        confidence: Double = 1.0,
        source: MemorySource = .explicitUser,
        reasonForRetention: String = "Explicit user request",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.key = key
        self.categoryRaw = category.rawValue
        self.content = content
        self.importance = importance
        self.confidence = confidence
        self.sourceRaw = source.rawValue
        self.reasonForRetention = reasonForRetention
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }
}

