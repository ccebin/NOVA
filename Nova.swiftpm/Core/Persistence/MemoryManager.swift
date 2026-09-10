import Foundation
import SwiftData
import os

@MainActor
public final class MemoryManager: ObservableObject {
    public static let shared = MemoryManager()
    
    private let logger = Logger(subsystem: "com.nova.assistant", category: "MemoryManager")
    private var localContext: ModelContext?
    
    // In-memory cache for deterministic testing and fast lookups
    private var inMemoryMemories: [String: MemoryEntity] = [:]
    
    public init(modelContext: ModelContext? = nil) {
        self.localContext = modelContext
    }
    
    public func setModelContext(_ context: ModelContext) {
        self.localContext = context
    }
    
    // MARK: - Save or Update (Deduplication & Update-in-Place)
    
    @discardableResult
    public func saveOrUpdateMemory(
        key: String,
        content: String,
        category: MemoryCategory = .general,
        importance: Int = 3,
        confidence: Double = 1.0,
        source: MemorySource = .explicitUser,
        reasonForRetention: String = "Explicit user instruction",
        expiresAt: Date? = nil
    ) -> MemoryEntity {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Check existing in SwiftData if context available
        if let mc = localContext {
            let descriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate<MemoryEntity> { $0.key == normalizedKey }
            )
            if let existingList = try? mc.fetch(descriptor), let existing = existingList.first {
                // Update in place (Deduplication: existing memory replaced with new state)
                existing.content = trimmedContent
                existing.category = category
                existing.importance = importance
                existing.confidence = confidence
                existing.source = source
                existing.reasonForRetention = reasonForRetention
                existing.updatedAt = Date()
                existing.expiresAt = expiresAt
                
                try? mc.save()
                inMemoryMemories[normalizedKey] = existing
                logger.info("Updated existing memory in place for key: \(normalizedKey)")
                return existing
            }
        }
        
        // 2. Check in-memory fallback cache
        if let existing = inMemoryMemories[normalizedKey] {
            existing.content = trimmedContent
            existing.category = category
            existing.importance = importance
            existing.confidence = confidence
            existing.source = source
            existing.reasonForRetention = reasonForRetention
            existing.updatedAt = Date()
            existing.expiresAt = expiresAt
            return existing
        }
        
        // 3. Create new entity
        let newMemory = MemoryEntity(
            key: normalizedKey,
            category: category,
            content: trimmedContent,
            importance: importance,
            confidence: confidence,
            source: source,
            reasonForRetention: reasonForRetention,
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: expiresAt
        )
        
        if let mc = localContext {
            mc.insert(newMemory)
            try? mc.save()
        }
        
        inMemoryMemories[normalizedKey] = newMemory
        logger.info("Persisted new memory for key: \(normalizedKey)")
        return newMemory
    }
    
    // MARK: - Relevance Retrieval (Non-Blind, Scored Retrieval)
    
    public func retrieveRelevantMemories(for query: String, limit: Int = 4) -> [MemoryEntity] {
        let all = fetchAllMemories()
        guard !all.isEmpty else { return [] }
        
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else { return [] }
        
        var scored: [(memory: MemoryEntity, score: Double)] = []
        
        for mem in all {
            // Check expiration
            if let exp = mem.expiresAt, exp < Date() {
                continue
            }
            
            let memTokens = tokenize(mem.key + " " + mem.content)
            let intersection = queryTokens.intersection(memTokens)
            
            // If zero term overlap, score is 0. NEVER blindly inject irrelevant memories.
            guard !intersection.isEmpty else { continue }
            
            let overlapRatio = Double(intersection.count) / Double(queryTokens.count)
            let importanceWeight = Double(mem.importance) / 5.0
            let confidenceWeight = mem.confidence
            
            // Recency factor (up to 20% boost for memories updated within last 7 days)
            let ageInSeconds = Date().timeIntervalSince(mem.updatedAt)
            let recencyBonus = max(0.0, 1.0 - (ageInSeconds / (86400.0 * 7.0))) * 0.2
            
            let totalScore = (overlapRatio * 0.6) + (importanceWeight * 0.2) + (confidenceWeight * 0.1) + recencyBonus
            
            scored.append((memory: mem, score: totalScore))
        }
        
        // Sort descending by score
        scored.sort { $0.score > $1.score }
        
        let results = scored.prefix(limit).map { $0.memory }
        logger.info("Retrieved \(results.count) relevant memories for query: '\(query)'")
        return Array(results)
    }
    
    // MARK: - Fetch All & Deletion
    
    public func fetchAllMemories() -> [MemoryEntity] {
        if let mc = localContext {
            let descriptor = FetchDescriptor<MemoryEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            if let list = try? mc.fetch(descriptor), !list.isEmpty {
                // Sync in-memory map
                for item in list {
                    inMemoryMemories[item.key] = item
                }
                return list
            }
        }
        return Array(inMemoryMemories.values).sorted { $0.updatedAt > $1.updatedAt }
    }
    
    public func deleteMemory(id: UUID) {
        if let mc = localContext {
            let descriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate<MemoryEntity> { $0.id == id }
            )
            if let items = try? mc.fetch(descriptor) {
                for item in items {
                    inMemoryMemories.removeValue(forKey: item.key)
                    mc.delete(item)
                }
                try? mc.save()
            }
        } else {
            inMemoryMemories = inMemoryMemories.filter { $0.value.id != id }
        }
    }
    
    public func deleteAllMemories() {
        if let mc = localContext {
            let all = (try? mc.fetch(FetchDescriptor<MemoryEntity>())) ?? []
            for item in all {
                mc.delete(item)
            }
            try? mc.save()
        }
        inMemoryMemories.removeAll()
    }
    
    // MARK: - Conservative Memory Extraction Classifier
    
    /// Evaluates whether a statement warrants permanent memory creation.
    /// Explicit requests are always persisted; casual/transient statements are rejected.
    public func shouldExtractMemory(from text: String) -> (shouldSave: Bool, key: String?, content: String?, category: MemoryCategory, confidence: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        
        // Pattern 1: Explicit user request to remember
        let explicitPrefixes = [
            "remember that",
            "remember:",
            "hatırla:",
            "hatırla ki",
            "save this:",
            "note that",
            "please remember"
        ]
        
        for prefix in explicitPrefixes {
            if lower.hasPrefix(prefix) {
                let remainder = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    let key = generateKey(from: remainder)
                    let category = inferCategory(from: remainder)
                    return (true, key, remainder, category, 1.0)
                }
            }
        }
        
        // Pattern 2: Explicit preference statements ("I prefer X", "My favorite X is Y")
        if lower.hasPrefix("i prefer ") || lower.hasPrefix("my favorite ") || lower.hasPrefix("always use ") {
            let key = generateKey(from: trimmed)
            return (true, key, trimmed, .userPreference, 0.9)
        }
        
        // Casual statements (e.g. "I used a dark theme today") are NOT permanent memory
        return (false, nil, nil, .general, 0.3)
    }
    
    // MARK: - Tokenizer & Key Helpers
    
    private func tokenize(_ text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "in", "to", "of", "and", "or", "for", "on", "at",
            "with", "by", "from", "up", "about", "into", "over", "after", "that", "this",
            "i", "my", "me", "you", "your", "he", "she", "it", "we", "they", "bir", "ve", "ile", "de", "da"
        ]
        let cleaned = text.lowercased().map { char -> Character in
            char.isLetter || char.isNumber ? char : " "
        }
        let words = String(cleaned).components(separatedBy: .whitespaces)
        let filtered = words.filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(filtered)
    }
    
    private func generateKey(from text: String) -> String {
        let tokens = Array(tokenize(text)).sorted()
        let prefix = tokens.prefix(3).joined(separator: ".")
        return prefix.isEmpty ? "memory.\(UUID().uuidString.prefix(8))" : "memory.\(prefix)"
    }
    
    private func inferCategory(from text: String) -> MemoryCategory {
        let lower = text.lowercased()
        if lower.contains("prefer") || lower.contains("like") || lower.contains("favorite") {
            return .userPreference
        }
        if lower.contains("decided") || lower.contains("decision") || lower.contains("chose") {
            return .pastDecision
        }
        if lower.contains("project") || lower.contains("building") || lower.contains("app") {
            return .project
        }
        if lower.contains("always") || lower.contains("recurring") || lower.contains("every") {
            return .recurringPreference
        }
        return .stableFact
    }
}
