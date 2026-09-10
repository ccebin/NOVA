import Foundation
import EventKit

public final class CalendarTool: NovaTool, @unchecked Sendable {
    public let definition: ToolDefinition
    private let eventStore: EKEventStore
    
    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.definition = ToolDefinition(
            id: "com.nova.tools.calendar.create",
            name: "Create Calendar Event",
            description: "Creates and verifies a personal event in Apple Calendar.",
            riskLevel: .lowRiskWrite,
            arguments: [
                ToolArgumentDefinition(name: "title", typeDescription: "string", description: "The event title.", isRequired: true),
                ToolArgumentDefinition(name: "startDate", typeDescription: "date", description: "Event start date/time (ISO-8601 or YYYY-MM-DD HH:mm).", isRequired: true),
                ToolArgumentDefinition(name: "endDate", typeDescription: "date", description: "Optional event end date/time (defaults to +1 hour).", isRequired: false),
                ToolArgumentDefinition(name: "location", typeDescription: "string", description: "Optional event location.", isRequired: false),
                ToolArgumentDefinition(name: "notes", typeDescription: "string", description: "Optional notes.", isRequired: false)
            ]
        )
    }
    
    public func checkPermission() async -> ToolPermissionStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
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
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }
    
    public func captureBeforeState(arguments: ToolArguments) async throws -> ToolObservation? {
        guard let startDate = arguments.date(for: "startDate") else {
            return ToolObservation(properties: ["conflictsCount": "0"])
        }
        
        let endDate = arguments.date(for: "endDate") ?? startDate.addingTimeInterval(3600)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let overlapping = eventStore.events(matching: predicate)
        
        return ToolObservation(properties: [
            "conflictsCount": "\(overlapping.count)",
            "windowStart": ISO8601DateFormatter().string(from: startDate),
            "windowEnd": ISO8601DateFormatter().string(from: endDate)
        ])
    }
    
    public func execute(arguments: ToolArguments, context: ToolExecutionContext) async throws -> ToolExecutionOutput {
        guard let title = arguments.string(for: "title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.missingParameter("title")
        }
        
        guard let startDate = arguments.date(for: "startDate") else {
            throw ToolExecutionError.missingParameter("startDate")
        }
        
        let endDate = arguments.date(for: "endDate") ?? startDate.addingTimeInterval(3600)
        
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ToolExecutionError.systemResourceUnavailable("No default Apple Calendar found.")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        
        if let loc = arguments.string(for: "location") {
            event.location = loc
        }
        if let notes = arguments.string(for: "notes") {
            event.notes = notes
        }
        
        try eventStore.save(event, span: .thisEvent, commit: true)
        
        return ToolExecutionOutput(
            primaryIdentifier: event.eventIdentifier,
            outputValues: [
                "identifier": event.eventIdentifier,
                "title": event.title ?? "",
                "calendar": calendar.title
            ]
        )
    }
    
    public func observeAfterState(arguments: ToolArguments, executionOutput: ToolExecutionOutput) async throws -> ToolObservation {
        let identifier = executionOutput.primaryIdentifier
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw ToolExecutionError.observationFailed("Could not locate created event with identifier: \(identifier)")
        }
        
        let iso = ISO8601DateFormatter()
        var props: [String: String] = [
            "identifier": event.eventIdentifier,
            "title": event.title ?? "",
            "calendar": event.calendar?.title ?? "Unknown",
            "startDate": iso.string(from: event.startDate),
            "endDate": iso.string(from: event.endDate)
        ]
        if let loc = event.location {
            props["location"] = loc
        }
        
        return ToolObservation(snapshotId: identifier, timestamp: Date(), properties: props)
    }
    
    public func verify(expected: ToolArguments, before: ToolObservation?, after: ToolObservation) async -> VerificationOutcome {
        var mismatches: [String] = []
        
        guard let expectedTitle = expected.string(for: "title") else {
            return VerificationOutcome(isVerified: false, explanation: "Missing expected title in arguments.")
        }
        
        guard let observedTitle = after.properties["title"] else {
            return VerificationOutcome(isVerified: false, explanation: "Event was not found in observed state.")
        }
        
        if observedTitle != expectedTitle {
            mismatches.append("Title mismatch: expected '\(expectedTitle)', observed '\(observedTitle)'")
        }
        
        let iso = ISO8601DateFormatter()
        if let expectedStart = expected.date(for: "startDate") {
            if let observedStartStr = after.properties["startDate"], let observedStart = iso.date(from: observedStartStr) {
                let diff = abs(observedStart.timeIntervalSince(expectedStart))
                if diff > 60.0 {
                    mismatches.append("Start date mismatch: expected '\(expectedStart)', observed '\(observedStart)' (diff: \(Int(diff))s)")
                }
            } else {
                mismatches.append("Observed event missing valid start date.")
            }
        }
        
        if mismatches.isEmpty {
            let cal = after.properties["calendar"] ?? "Calendar"
            return VerificationOutcome(
                isVerified: true,
                explanation: "Confirmed event '\(expectedTitle)' exists in '\(cal)'."
            )
        } else {
            return VerificationOutcome(
                isVerified: false,
                mismatches: mismatches,
                explanation: mismatches.joined(separator: "; ")
            )
        }
    }
}
