import Foundation
import Security

/// Errors related to Gemini API Key retrieval and storage.
public enum GeminiKeyError: LocalizedError, Sendable, Equatable {
    case noKeyConfigured
    case keychainError(OSStatus)
    case invalidKeyFormat
    
    public var errorDescription: String? {
        switch self {
        case .noKeyConfigured:
            return "No Google Gemini API key configured. Please enter your key in Settings."
        case .keychainError(let status):
            return "Secure storage operation failed with OSStatus code \(status)."
        case .invalidKeyFormat:
            return "The provided Gemini API key format is invalid."
        }
    }
}

/// Helper for masking secret keys in UI, logs, and diagnostics without leaking plaintext.
public struct GeminiKeyMasker: Sendable {
    public static func mask(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 8 {
            return String(repeating: "•", count: trimmed.count)
        }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)••••••••\(suffix)"
    }
}

/// Abstract provider protocol for obtaining and managing Google Gemini API keys securely.
public protocol GeminiKeyProvider: Sendable {
    func getApiKey() async throws -> String
    func saveApiKey(_ key: String) throws
    func deleteApiKey() throws
    var hasKey: Bool { get }
    var maskedKey: String { get }
}

/// Secure implementation using Apple's Security framework (Keychain).
/// Plaintext secrets are NEVER written to UserDefaults or disk files.
public final class KeychainGeminiKeyProvider: GeminiKeyProvider, @unchecked Sendable {
    private let service: String
    private let account: String
    private let lock = NSLock()
    
    public init(
        service: String = "com.nova.assistant.gemini",
        account: String = "gemini_api_key"
    ) {
        self.service = service
        self.account = account
    }
    
    public var hasKey: Bool {
        (try? getApiKeySync()) != nil
    }
    
    public var maskedKey: String {
        guard let raw = try? getApiKeySync() else { return "" }
        return GeminiKeyMasker.mask(raw)
    }
    
    public func getApiKey() async throws -> String {
        try getApiKeySync()
    }
    
    private func getApiKeySync() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw GeminiKeyError.noKeyConfigured
            }
            throw GeminiKeyError.keychainError(status)
        }
        
        return key
    }
    
    public func saveApiKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteApiKey()
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = trimmed.data(using: .utf8) else {
            throw GeminiKeyError.invalidKeyFormat
        }
        
        // Delete existing item first to ensure clean state
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new item with device-only accessibility
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GeminiKeyError.keychainError(status)
        }
    }
    
    public func deleteApiKey() throws {
        lock.lock()
        defer { lock.unlock() }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GeminiKeyError.keychainError(status)
        }
    }
}

/// Key provider that retrieves key from environment variable (useful in CI or test runners).
public final class EnvironmentGeminiKeyProvider: GeminiKeyProvider, Sendable {
    private let variableName: String
    
    public init(variableName: String = "GEMINI_API_KEY") {
        self.variableName = variableName
    }
    
    public var hasKey: Bool {
        guard let raw = ProcessInfo.processInfo.environment[variableName], !raw.isEmpty else {
            return false
        }
        return true
    }
    
    public var maskedKey: String {
        guard let raw = ProcessInfo.processInfo.environment[variableName] else { return "" }
        return GeminiKeyMasker.mask(raw)
    }
    
    public func getApiKey() async throws -> String {
        guard let raw = ProcessInfo.processInfo.environment[variableName], !raw.isEmpty else {
            throw GeminiKeyError.noKeyConfigured
        }
        return raw
    }
    
    public func saveApiKey(_ key: String) throws {
        // Environment variables cannot be permanently written in-process on iOS
    }
    
    public func deleteApiKey() throws {
        // No-op for environment
    }
}

/// Composite key provider: Checks Keychain first, then Environment variables.
public final class CompositeGeminiKeyProvider: GeminiKeyProvider, Sendable {
    private let keychainProvider: KeychainGeminiKeyProvider
    private let envProvider: EnvironmentGeminiKeyProvider
    
    public init(
        keychain: KeychainGeminiKeyProvider = KeychainGeminiKeyProvider(),
        env: EnvironmentGeminiKeyProvider = EnvironmentGeminiKeyProvider()
    ) {
        self.keychainProvider = keychain
        self.envProvider = env
    }
    
    public var hasKey: Bool {
        keychainProvider.hasKey || envProvider.hasKey
    }
    
    public var maskedKey: String {
        if keychainProvider.hasKey {
            return keychainProvider.maskedKey
        }
        return envProvider.maskedKey
    }
    
    public func getApiKey() async throws -> String {
        if let key = try? await keychainProvider.getApiKey(), !key.isEmpty {
            return key
        }
        return try await envProvider.getApiKey()
    }
    
    public func saveApiKey(_ key: String) throws {
        try keychainProvider.saveApiKey(key)
    }
    
    public func deleteApiKey() throws {
        try keychainProvider.deleteApiKey()
    }
}

/// In-memory mock key provider for deterministic tests.
public final class MockGeminiKeyProvider: GeminiKeyProvider, @unchecked Sendable {
    private var key: String?
    private let lock = NSLock()
    
    public init(initialKey: String? = nil) {
        self.key = initialKey
    }
    
    public var hasKey: Bool {
        lock.lock()
        defer { lock.unlock() }
        return key != nil && !(key?.isEmpty ?? true)
    }
    
    public var maskedKey: String {
        lock.lock()
        defer { lock.unlock() }
        guard let k = key else { return "" }
        return GeminiKeyMasker.mask(k)
    }
    
    public func getApiKey() async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let k = key, !k.isEmpty else {
            throw GeminiKeyError.noKeyConfigured
        }
        return k
    }
    
    public func saveApiKey(_ newKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        self.key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func deleteApiKey() throws {
        lock.lock()
        defer { lock.unlock() }
        self.key = nil
    }
}
