import Foundation
import EventKit

public final class RemindersTool: NovaTool, @unchecked Sendable {
    public let definition: ToolDefinition
    private let eventStore: EKEventStore
    
    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.definition = ToolDefinition(
            id: "com.nova.tools.reminders.create",
            name: "Create Reminder",
            description: "Creates and verifies a personal reminder in Apple Reminders.",
            riskLevel: .lowRiskWrite,
            arguments: [
                ToolArgumentDefinition(name: "title", typeDescription: "string", description: "The task or reminder title.", isRequired: true),
                ToolArgumentDefinition(name: "dueDate", typeDescription: "date", description: "Optional due date (ISO-8601 or YYYY-MM-DD HH:mm).", isRequired: false),
                ToolArgumentDefinition(name: "notes", typeDescription: "string", description: "Optional notes or details.", isRequired: false)
            ]
        )
    }
    
    public func checkPermission() async -> ToolPermissionStatus {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined, .writeOnly:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
    
    public func requestPermission() async -> ToolPermissionStatus {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToReminders()
            } else {
                granted = try await eventStore.requestAccess(to: .reminder)
            }
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }
    
    public func captureBeforeState(arguments: ToolArguments) async throws -> ToolObservation? {
        guard let title = arguments.string(for: "title") else {
            return ToolObservation(properties: ["existingMatchingCount": "0"])
        }
        
        let matchingCount = await countReminders(matching: title)
        return ToolObservation(properties: [
            "existingMatchingCount": "\(matchingCount)",
            "queryTitle": title
        ])
    }
    
    public func execute(arguments: ToolArguments, context: ToolExecutionContext) async throws -> ToolExecutionOutput {
        guard let title = arguments.string(for: "title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.missingParameter("title")
        }
        
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ToolExecutionError.systemResourceUnavailable("No default Reminders calendar found.")
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        
        if let notes = arguments.string(for: "notes") {
            reminder.notes = notes
        }
        
        if let dueDate = arguments.date(for: "dueDate") {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }
        
        try eventStore.save(reminder, commit: true)
        
        return ToolExecutionOutput(
            primaryIdentifier: reminder.calendarItemIdentifier,
            outputValues: [
                "identifier": reminder.calendarItemIdentifier,
                "title": reminder.title ?? "",
                "calendar": calendar.title
            ]
        )
    }
    
    public func observeAfterState(arguments: ToolArguments, executionOutput: ToolExecutionOutput) async throws -> ToolObservation {
        let identifier = executionOutput.primaryIdentifier
        guard let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ToolExecutionError.observationFailed("Could not locate created reminder with identifier: \(identifier)")
        }
        
        var props: [String: String] = [
            "identifier": item.calendarItemIdentifier,
            "title": item.title ?? "",
            "calendar": item.calendar?.title ?? "Unknown",
            "isCompleted": "\(item.isCompleted)"
        ]
        
        if let dueDateComp = item.dueDateComponents, let date = Calendar.current.date(from: dueDateComp) {
            let iso = ISO8601DateFormatter()
            props["dueDate"] = iso.string(from: date)
        }
        
        return ToolObservation(snapshotId: identifier, timestamp: Date(), properties: props)
    }
    
    public func verify(expected: ToolArguments, before: ToolObservation?, after: ToolObservation) async -> VerificationOutcome {
        var mismatches: [String] = []
        
        guard let expectedTitle = expected.string(for: "title") else {
            return VerificationOutcome(isVerified: false, explanation: "Missing expected title in arguments.")
        }
        
        guard let observedTitle = after.properties["title"] else {
            return VerificationOutcome(isVerified: false, explanation: "Reminder was not found in observed state.")
        }
        
        if observedTitle != expectedTitle {
            mismatches.append("Title mismatch: expected '\(expectedTitle)', observed '\(observedTitle)'")
        }
        
        if let expectedDate = expected.date(for: "dueDate") {
            if let observedDateStr = after.properties["dueDate"],
               let observedDate = ISO8601DateFormatter().date(from: observedDateStr) {
                let diff = abs(observedDate.timeIntervalSince(expectedDate))
                if diff > 60.0 {
                    mismatches.append("Due date mismatch: expected '\(expectedDate)', observed '\(observedDate)' (diff: \(Int(diff))s)")
                }
            } else {
                mismatches.append("Expected due date was not set on the observed reminder.")
            }
        }
        
        if mismatches.isEmpty {
            let cal = after.properties["calendar"] ?? "Reminders"
            return VerificationOutcome(
                isVerified: true,
                explanation: "Confirmed reminder '\(expectedTitle)' exists in '\(cal)'."
            )
        } else {
            return VerificationOutcome(
                isVerified: false,
                mismatches: mismatches,
                explanation: mismatches.joined(separator: "; ")
            )
        }
    }
    
    // MARK: - Helper Query
    
    private func countReminders(matching title: String) async -> Int {
        await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let count = (reminders ?? []).filter { $0.title == title }.count
                continuation.resume(returning: count)
            }
        }
    }
}

public enum ToolExecutionError: LocalizedError, Sendable {
    case missingParameter(String)
    case systemResourceUnavailable(String)
    case observationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingParameter(let p):
            return "Missing required parameter: \(p)"
        case .systemResourceUnavailable(let r):
            return "System resource unavailable: \(r)"
        case .observationFailed(let msg):
            return "State observation failed: \(msg)"
        }
    }
}
