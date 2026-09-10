import Foundation
import SwiftData
import os

@MainActor
public final class LocalDataManager: ObservableObject {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.nova.assistant", category: "Persistence")
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    public func getOrCreateActiveConversation() -> ConversationEntity {
        let descriptor = FetchDescriptor<ConversationEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            let existingList = try modelContext.fetch(descriptor)
            if let existing = existingList.first {
                return existing
            }
        } catch {
            logger.error("Failed to fetch existing conversations: \(error.localizedDescription)")
        }
        
        let newConversation = ConversationEntity(title: "NOVA Session")
        modelContext.insert(newConversation)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save new conversation: \(error.localizedDescription)")
        }
        return newConversation
    }
    
    public func addMessage(
        role: MessageRoleEnum,
        content: String,
        to conversation: ConversationEntity,
        toolName: String? = nil,
        toolStatus: ToolStatus? = nil,
        toolVerificationPassed: Bool? = nil,
        toolExplanation: String? = nil,
        toolDiffSummary: String? = nil
    ) -> MessageEntity {
        let message = MessageEntity(
            role: role,
            content: content,
            timestamp: Date(),
            conversation: conversation,
            toolName: toolName,
            toolStatus: toolStatus,
            toolVerificationPassed: toolVerificationPassed,
            toolExplanation: toolExplanation,
            toolDiffSummary: toolDiffSummary
        )
        modelContext.insert(message)
        
        // Ensure bidirectional relationship is immediately synced in-memory
        if conversation.messages == nil {
            conversation.messages = [message]
        } else {
            conversation.messages?.append(message)
        }
        
        conversation.updatedAt = Date()
        if conversation.title == "New Conversation" || conversation.title == "NOVA Session" {
            let preview = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preview.isEmpty {
                let firstLine = preview.components(separatedBy: .newlines).first ?? preview
                conversation.title = String(firstLine.prefix(32))
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save message: \(error.localizedDescription)")
        }
        return message
    }
    
    public func fetchAllConversations() -> [ConversationEntity] {
        let descriptor = FetchDescriptor<ConversationEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch all conversations: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Reads messages reliably without relying on problematic iOS 17 relationship #Predicate keypath traversal.
    public func fetchMessages(for conversation: ConversationEntity) -> [MessageEntity] {
        // Approach A: Read directly through the SwiftData relationship inverse
        if let directMessages = conversation.messages, !directMessages.isEmpty {
            return directMessages.sorted { $0.timestamp < $1.timestamp }
        }
        
        // Approach B: Fallback fetch of MessageEntity sorted by timestamp, filtered safely in-memory
        let descriptor = FetchDescriptor<MessageEntity>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let allMessages = try modelContext.fetch(descriptor)
            let filtered = allMessages.filter { $0.conversation?.id == conversation.id }
            return filtered
        } catch {
            logger.error("Failed to fetch messages fallback: \(error.localizedDescription)")
            return []
        }
    }
    
    public func getStorageStats() -> (conversationsCount: Int, messagesCount: Int) {
        do {
            let convCount = try modelContext.fetchCount(FetchDescriptor<ConversationEntity>())
            let msgCount = try modelContext.fetchCount(FetchDescriptor<MessageEntity>())
            return (convCount, msgCount)
        } catch {
            logger.error("Failed to fetch storage stats: \(error.localizedDescription)")
            return (0, 0)
        }
    }
    
    public func deleteAllConversations() {
        let conversations = fetchAllConversations()
        for conv in conversations {
            modelContext.delete(conv)
        }
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to delete conversations: \(error.localizedDescription)")
        }
    }
    
    public func exportDataAsJSON() -> String {
        let conversations = fetchAllConversations()
        var exportArray: [[String: Any]] = []
        
        let isoFormatter = ISO8601DateFormatter()
        
        for conv in conversations {
            let messages = fetchMessages(for: conv)
            let msgDicts: [[String: String]] = messages.map { msg in
                [
                    "id": msg.id.uuidString,
                    "role": msg.roleRaw,
                    "content": msg.content,
                    "timestamp": isoFormatter.string(from: msg.timestamp)
                ]
            }
            
            exportArray.append([
                "id": conv.id.uuidString,
                "title": conv.title,
                "createdAt": isoFormatter.string(from: conv.createdAt),
                "updatedAt": isoFormatter.string(from: conv.updatedAt),
                "messages": msgDicts
            ])
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportArray, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }
        return jsonString
    }
}
