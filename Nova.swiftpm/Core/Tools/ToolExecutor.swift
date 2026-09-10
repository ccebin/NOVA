import Foundation
import SwiftData
import os

@MainActor
public final class ToolExecutor: ObservableObject {
    public static let shared = ToolExecutor()
    
    private let logger = Logger(subsystem: "com.nova.assistant", category: "ToolExecutor")
    private var completedIdempotencyKeys: Set<String> = []
    
    public init() {}
    
    public func execute(
        tool: any NovaTool,
        arguments: ToolArguments,
        context: ToolExecutionContext,
        modelContext: ModelContext? = nil
    ) async -> ToolResult {
        let startTime = Date()
        let toolId = tool.definition.id
        let toolName = tool.definition.name
        
        // 1. Idempotency / Duplicate Execution Protection
        if let key = context.idempotencyKey {
            if completedIdempotencyKeys.contains(key) {
                logger.warning("Duplicate execution prevented for key: \(key)")
                return ToolResult(
                    toolId: toolId,
                    toolName: toolName,
                    status: .cancelled,
                    message: "Duplicate action prevented by idempotency check.",
                    durationMs: 0.0
                )
            }
        }
        
        // 2. Argument Schema Validation
        let missingOrInvalid = arguments.validate(against: tool.definition.arguments)
        if !missingOrInvalid.isEmpty {
            let errorMsg = "Invalid arguments: \(missingOrInvalid.joined(separator: ", "))"
            logger.error("\(errorMsg)")
            let result = ToolResult(
                toolId: toolId,
                toolName: toolName,
                status: .invalidArguments,
                message: errorMsg,
                durationMs: 0.0
            )
            persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
            return result
        }
        
        // 3. Generic Safety Policy
        switch tool.definition.riskLevel {
        case .readOnly, .lowRiskWrite:
            break
        case .highRiskDestructive:
            if !context.isUserConfirmed {
                let msg = "Action requires explicit user confirmation before execution."
                logger.info("\(msg)")
                let result = ToolResult(
                    toolId: toolId,
                    toolName: toolName,
                    status: .cancelled,
                    message: msg,
                    durationMs: 0.0
                )
                persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
                return result
            }
        }
        
        // 4. Permission Checking & Requesting
        var permission = await tool.checkPermission()
        if permission == .notDetermined {
            permission = await tool.requestPermission()
        }
        
        guard permission == .authorized else {
            let msg = "Permission \(permission.rawValue) for \(toolName)."
            logger.error("\(msg)")
            let result = ToolResult(
                toolId: toolId,
                toolName: toolName,
                status: .permissionDenied,
                message: msg,
                durationMs: 0.0
            )
            persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
            return result
        }
        
        // 5. Capture BEFORE STATE
        var beforeState: ToolObservation? = nil
        do {
            beforeState = try await tool.captureBeforeState(arguments: arguments)
        } catch {
            logger.warning("Could not capture before state: \(error.localizedDescription)")
        }
        
        // 6. ACTION Execution
        let executionOutput: ToolExecutionOutput
        do {
            executionOutput = try await tool.execute(arguments: arguments, context: context)
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            let errorMsg = "Action execution failed: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            let result = ToolResult(
                toolId: toolId,
                toolName: toolName,
                status: .failed,
                message: errorMsg,
                beforeState: beforeState,
                durationMs: duration
            )
            persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
            return result
        }
        
        // 7. Capture OBSERVATION / AFTER STATE
        let afterState: ToolObservation
        do {
            afterState = try await tool.observeAfterState(arguments: arguments, executionOutput: executionOutput)
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            let errorMsg = "Could not observe state after action: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            let result = ToolResult(
                toolId: toolId,
                toolName: toolName,
                status: .failed,
                message: errorMsg,
                beforeState: beforeState,
                durationMs: duration
            )
            persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
            return result
        }
        
        // 8. Compute STATE DIFF
        let diff = StateDiff(before: beforeState, after: afterState)
        
        // 9. VERIFICATION
        let verification = await tool.verify(expected: arguments, before: beforeState, after: afterState)
        let duration = Date().timeIntervalSince(startTime) * 1000.0
        
        guard verification.isVerified else {
            let errorMsg = "Verification failed: \(verification.explanation)"
            logger.error("\(errorMsg)")
            let result = ToolResult(
                toolId: toolId,
                toolName: toolName,
                status: .verificationFailed,
                message: errorMsg,
                beforeState: beforeState,
                afterState: afterState,
                diff: diff,
                verification: verification,
                outputData: executionOutput.outputValues,
                durationMs: duration
            )
            persistRecord(result: result, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
            return result
        }
        
        // 10. Success & Idempotency Registration
        if let key = context.idempotencyKey {
            completedIdempotencyKeys.insert(key)
        }
        
        let successResult = ToolResult(
            toolId: toolId,
            toolName: toolName,
            status: .success,
            message: "Action verified successfully: \(verification.explanation)",
            beforeState: beforeState,
            afterState: afterState,
            diff: diff,
            verification: verification,
            outputData: executionOutput.outputValues,
            durationMs: duration
        )
        
        persistRecord(result: successResult, arguments: arguments, startTime: startTime, endTime: Date(), context: context, modelContext: modelContext)
        return successResult
    }
    
    private func persistRecord(
        result: ToolResult,
        arguments: ToolArguments,
        startTime: Date,
        endTime: Date,
        context: ToolExecutionContext,
        modelContext: ModelContext?
    ) {
        guard let mc = modelContext else { return }
        
        let argsJSON = (try? String(data: JSONSerialization.data(withJSONObject: arguments.storage), encoding: .utf8)) ?? "{}"
        let beforeJSON = result.beforeState != nil ? (try? String(data: JSONSerialization.data(withJSONObject: result.beforeState!.properties), encoding: .utf8)) : nil
        let afterJSON = result.afterState != nil ? (try? String(data: JSONSerialization.data(withJSONObject: result.afterState!.properties), encoding: .utf8)) : nil
        
        let record = ToolExecutionRecordEntity(
            toolId: result.toolId,
            toolName: result.toolName,
            argumentsJSON: argsJSON,
            startTime: startTime,
            endTime: endTime,
            durationMs: result.durationMs,
            beforeStateJSON: beforeJSON,
            afterStateJSON: afterJSON,
            diffSummary: result.diff?.summary,
            verificationPassed: result.verification?.isVerified ?? (result.status == .success),
            verificationExplanation: result.verification?.explanation ?? result.message,
            finalStatus: result.status,
            errorMessage: result.status != .success ? result.message : nil,
            idempotencyKey: context.idempotencyKey
        )
        
        mc.insert(record)
        do {
            try mc.save()
        } catch {
            logger.error("Failed to save ToolExecutionRecord: \(error.localizedDescription)")
        }
    }
}
