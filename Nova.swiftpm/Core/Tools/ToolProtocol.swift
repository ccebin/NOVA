import Foundation

public enum ToolRiskLevel: String, Codable, Sendable {
    case readOnly = "Read-Only"
    case lowRiskWrite = "Low-Risk Write"
    case highRiskDestructive = "High-Risk Destructive"
}

public enum ToolStatus: String, Codable, Sendable {
    case success = "Success"
    case failed = "Failed"
    case permissionDenied = "Permission Denied"
    case invalidArguments = "Invalid Arguments"
    case notFound = "Not Found"
    case verificationFailed = "Verification Failed"
    case cancelled = "Cancelled"
}

public enum ToolPermissionStatus: String, Codable, Sendable {
    case authorized = "Authorized"
    case denied = "Denied"
    case restricted = "Restricted"
    case notDetermined = "Not Determined"
}

public struct ToolArgumentDefinition: Sendable, Codable {
    public let name: String
    public let typeDescription: String // "string", "date", "int", "bool"
    public let description: String
    public let isRequired: Bool
    
    public init(name: String, typeDescription: String, description: String, isRequired: Bool = true) {
        self.name = name
        self.typeDescription = typeDescription
        self.description = description
        self.isRequired = isRequired
    }
}

public struct ToolDefinition: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let riskLevel: ToolRiskLevel
    public let arguments: [ToolArgumentDefinition]
    
    public init(id: String, name: String, description: String, riskLevel: ToolRiskLevel, arguments: [ToolArgumentDefinition]) {
        self.id = id
        self.name = name
        self.description = description
        self.riskLevel = riskLevel
        self.arguments = arguments
    }
}

public struct ToolArguments: Sendable {
    public let storage: [String: String]
    
    public init(_ storage: [String: String] = [:]) {
        self.storage = storage
    }
    
    public func string(for key: String) -> String? {
        storage[key]
    }
    
    public func date(for key: String) -> Date? {
        guard let str = storage[key] else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: str) {
            return date
        }
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        return fallbackFormatter.date(from: str)
    }
    
    public func bool(for key: String) -> Bool? {
        guard let str = storage[key]?.lowercased() else { return nil }
        if str == "true" || str == "yes" || str == "1" { return true }
        if str == "false" || str == "no" || str == "0" { return false }
        return nil
    }
    
    public func int(for key: String) -> Int? {
        guard let str = storage[key] else { return nil }
        return Int(str)
    }
    
    public func validate(against schema: [ToolArgumentDefinition]) -> [String] {
        var missingOrInvalid: [String] = []
        for argDef in schema where argDef.isRequired {
            if let val = storage[argDef.name], !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if argDef.typeDescription == "date" && date(for: argDef.name) == nil {
                    missingOrInvalid.append("\(argDef.name) (invalid date format)")
                }
            } else {
                missingOrInvalid.append("\(argDef.name) (required)")
            }
        }
        return missingOrInvalid
    }
}

public struct ToolObservation: Sendable, Codable {
    public let snapshotId: String
    public let timestamp: Date
    public let properties: [String: String]
    
    public init(snapshotId: String = UUID().uuidString, timestamp: Date = Date(), properties: [String: String]) {
        self.snapshotId = snapshotId
        self.timestamp = timestamp
        self.properties = properties
    }
}

public struct StateDiff: Sendable, Codable {
    public let changedKeys: [String]
    public let beforeValues: [String: String]
    public let afterValues: [String: String]
    public let summary: String
    
    public init(before: ToolObservation?, after: ToolObservation) {
        var keys: [String] = []
        var beforeDict: [String: String] = [:]
        var afterDict: [String: String] = [:]
        
        let allKeys = Set((before?.properties.keys.map { $0 } ?? []) + after.properties.keys.map { $0 })
        for key in allKeys {
            let bVal = before?.properties[key]
            let aVal = after.properties[key]
            if bVal != aVal {
                keys.append(key)
                if let b = bVal { beforeDict[key] = b }
                if let a = aVal { afterDict[key] = a }
            }
        }
        
        self.changedKeys = keys.sorted()
        self.beforeValues = beforeDict
        self.afterValues = afterDict
        
        if keys.isEmpty {
            self.summary = "No detected state changes."
        } else {
            let changes = keys.map { "\($0): '\(beforeDict[$0] ?? "none")' -> '\(afterDict[$0] ?? "none")'" }
            self.summary = changes.joined(separator: ", ")
        }
    }
}

public struct VerificationOutcome: Sendable, Codable {
    public let isVerified: Bool
    public let mismatches: [String]
    public let explanation: String
    
    public init(isVerified: Bool, mismatches: [String] = [], explanation: String) {
        self.isVerified = isVerified
        self.mismatches = mismatches
        self.explanation = explanation
    }
}

public struct ToolExecutionOutput: Sendable {
    public let primaryIdentifier: String
    public let outputValues: [String: String]
    
    public init(primaryIdentifier: String, outputValues: [String: String] = [:]) {
        self.primaryIdentifier = primaryIdentifier
        self.outputValues = outputValues
    }
}

public struct ToolExecutionContext: Sendable {
    public let idempotencyKey: String?
    public let isUserConfirmed: Bool
    
    public init(idempotencyKey: String? = nil, isUserConfirmed: Bool = false) {
        self.idempotencyKey = idempotencyKey
        self.isUserConfirmed = isUserConfirmed
    }
}

public struct ToolResult: Sendable {
    public let toolId: String
    public let toolName: String
    public let status: ToolStatus
    public let message: String
    public let beforeState: ToolObservation?
    public let afterState: ToolObservation?
    public let diff: StateDiff?
    public let verification: VerificationOutcome?
    public let outputData: [String: String]
    public let durationMs: Double
    
    public init(
        toolId: String,
        toolName: String,
        status: ToolStatus,
        message: String,
        beforeState: ToolObservation? = nil,
        afterState: ToolObservation? = nil,
        diff: StateDiff? = nil,
        verification: VerificationOutcome? = nil,
        outputData: [String: String] = [:],
        durationMs: Double = 0.0
    ) {
        self.toolId = toolId
        self.toolName = toolName
        self.status = status
        self.message = message
        self.beforeState = beforeState
        self.afterState = afterState
        self.diff = diff
        self.verification = verification
        self.outputData = outputData
        self.durationMs = durationMs
    }
}

public protocol NovaTool: Sendable {
    var definition: ToolDefinition { get }
    
    func checkPermission() async -> ToolPermissionStatus
    func requestPermission() async -> ToolPermissionStatus
    func captureBeforeState(arguments: ToolArguments) async throws -> ToolObservation?
    func execute(arguments: ToolArguments, context: ToolExecutionContext) async throws -> ToolExecutionOutput
    func observeAfterState(arguments: ToolArguments, executionOutput: ToolExecutionOutput) async throws -> ToolObservation
    func verify(expected: ToolArguments, before: ToolObservation?, after: ToolObservation) async -> VerificationOutcome
}
