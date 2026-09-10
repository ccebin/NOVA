import Foundation

/// Mock tool used to test all ToolExecutor lifecycle invariants deterministically
public final class MockVerificationTool: NovaTool, @unchecked Sendable {
    public let definition: ToolDefinition
    public var permissionToReturn: ToolPermissionStatus = .authorized
    public var shouldFailExecution: Bool = false
    public var simulateVerificationMismatch: Bool = false
    
    public init(
        id: String = "com.nova.tools.test.mock",
        name: String = "Mock Verified Tool",
        riskLevel: ToolRiskLevel = .lowRiskWrite
    ) {
        self.definition = ToolDefinition(
            id: id,
            name: name,
            description: "Mock tool for deterministic lifecycle testing.",
            riskLevel: riskLevel,
            arguments: [
                ToolArgumentDefinition(name: "title", typeDescription: "string", description: "Title argument.", isRequired: true),
                ToolArgumentDefinition(name: "date", typeDescription: "date", description: "Optional date.", isRequired: false)
            ]
        )
    }
    
    public func checkPermission() async -> ToolPermissionStatus {
        return permissionToReturn
    }
    
    public func requestPermission() async -> ToolPermissionStatus {
        return permissionToReturn
    }
    
    public func captureBeforeState(arguments: ToolArguments) async throws -> ToolObservation? {
        return ToolObservation(properties: ["count": "0", "status": "initial"])
    }
    
    public func execute(arguments: ToolArguments, context: ToolExecutionContext) async throws -> ToolExecutionOutput {
        if shouldFailExecution {
            throw ToolExecutionError.systemResourceUnavailable("Simulated execution failure.")
        }
        return ToolExecutionOutput(primaryIdentifier: "mock_123", outputValues: ["id": "mock_123"])
    }
    
    public func observeAfterState(arguments: ToolArguments, executionOutput: ToolExecutionOutput) async throws -> ToolObservation {
        let observedTitle = simulateVerificationMismatch ? "Wrong Title" : (arguments.string(for: "title") ?? "")
        return ToolObservation(
            snapshotId: executionOutput.primaryIdentifier,
            properties: [
                "id": executionOutput.primaryIdentifier,
                "title": observedTitle,
                "status": "created"
            ]
        )
    }
    
    public func verify(expected: ToolArguments, before: ToolObservation?, after: ToolObservation) async -> VerificationOutcome {
        let expectedTitle = expected.string(for: "title") ?? ""
        let observedTitle = after.properties["title"] ?? ""
        
        if expectedTitle == observedTitle {
            return VerificationOutcome(isVerified: true, explanation: "Title '\(expectedTitle)' verified in state.")
        } else {
            return VerificationOutcome(
                isVerified: false,
                mismatches: ["Title mismatch: expected '\(expectedTitle)', got '\(observedTitle)'"],
                explanation: "State verification mismatch."
            )
        }
    }
}

public struct TestResultReport: Sendable {
    public let testName: String
    public let passed: Bool
    public let detail: String
}

@MainActor
public enum ToolSystemTests {
    public static func runAllTests() async -> [TestResultReport] {
        var reports: [TestResultReport] = []
        
        reports.append(await testToolRegistration())
        reports.append(await testArgumentValidation())
        reports.append(await testPermissionDenied())
        reports.append(await testSuccessfulExecutionAndVerification())
        reports.append(await testFailedExecutionHandling())
        reports.append(await testVerificationFailureDetection())
        reports.append(await testSafetyPolicyConfirmation())
        reports.append(await testDuplicateExecutionProtection())
        reports.append(await testGenericToolRouter())
        
        return reports
    }
    
    // 1. Tool Registration
    public static func testToolRegistration() async -> TestResultReport {
        let registry = ToolRegistry()
        let tool = MockVerificationTool(id: "test.reg")
        registry.register(tool)
        
        let found = registry.tool(for: "test.reg")
        let pass = (found != nil && registry.allTools().count == 1)
        return TestResultReport(
            testName: "Tool Registration",
            passed: pass,
            detail: pass ? "Tool registered and discovered by ID." : "Tool registry lookup failed."
        )
    }
    
    // 2. Argument Validation
    public static func testArgumentValidation() async -> TestResultReport {
        let schema = [
            ToolArgumentDefinition(name: "title", typeDescription: "string", description: "Title", isRequired: true),
            ToolArgumentDefinition(name: "date", typeDescription: "date", description: "Date", isRequired: true)
        ]
        
        // Missing required arguments
        let emptyArgs = ToolArguments([:])
        let missing = emptyArgs.validate(against: schema)
        let pass1 = missing.count == 2
        
        // Invalid date format
        let invalidDateArgs = ToolArguments(["title": "Test", "date": "not-a-date"])
        let invalidDateErrors = invalidDateArgs.validate(against: schema)
        let pass2 = invalidDateErrors.contains(where: { $0.contains("invalid date format") })
        
        // Valid arguments
        let validArgs = ToolArguments(["title": "Test", "date": "2026-09-11 10:00"])
        let validErrors = validArgs.validate(against: schema)
        let pass3 = validErrors.isEmpty
        
        let allPass = pass1 && pass2 && pass3
        return TestResultReport(
            testName: "Argument Validation",
            passed: allPass,
            detail: allPass ? "Correctly validated required fields and date parsing." : "Validation checks failed."
        )
    }
    
    // 3. Permission Handling
    public static func testPermissionDenied() async -> TestResultReport {
        let executor = ToolExecutor()
        let tool = MockVerificationTool()
        tool.permissionToReturn = .denied
        
        let result = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Test"]),
            context: ToolExecutionContext()
        )
        
        let pass = (result.status == .permissionDenied)
        return TestResultReport(
            testName: "Permission Denied Handling",
            passed: pass,
            detail: pass ? "Returned .permissionDenied and halted execution." : "Did not halt on denied permission."
        )
    }
    
    // 4. Successful Execution & Verification
    public static func testSuccessfulExecutionAndVerification() async -> TestResultReport {
        let executor = ToolExecutor()
        let tool = MockVerificationTool()
        
        let result = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Buy Groceries"]),
            context: ToolExecutionContext()
        )
        
        let pass = (result.status == .success &&
                    result.verification?.isVerified == true &&
                    result.beforeState != nil &&
                    result.afterState != nil &&
                    result.diff != nil)
        return TestResultReport(
            testName: "Successful Execution & Verification",
            passed: pass,
            detail: pass ? "Passed beforeState -> action -> afterState -> diff -> verification." : "Lifecycle failure."
        )
    }
    
    // 5. Failed Execution Handling
    public static func testFailedExecutionHandling() async -> TestResultReport {
        let executor = ToolExecutor()
        let tool = MockVerificationTool()
        tool.shouldFailExecution = true
        
        let result = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Fail Test"]),
            context: ToolExecutionContext()
        )
        
        let pass = (result.status == .failed)
        return TestResultReport(
            testName: "Execution Failure Handling",
            passed: pass,
            detail: pass ? "Correctly captured error and returned .failed status." : "Unexpected status on execution failure."
        )
    }
    
    // 6. Verification Failure Detection
    public static func testVerificationFailureDetection() async -> TestResultReport {
        let executor = ToolExecutor()
        let tool = MockVerificationTool()
        tool.simulateVerificationMismatch = true // Action succeeds, but state does not match!
        
        let result = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Expected Title"]),
            context: ToolExecutionContext()
        )
        
        // Invariant: If afterState does not match expected, MUST return .verificationFailed!
        let pass = (result.status == .verificationFailed && result.verification?.isVerified == false)
        return TestResultReport(
            testName: "Verification Failure Detection",
            passed: pass,
            detail: pass ? "Correctly detected state mismatch and returned .verificationFailed." : "Failed to catch state mismatch!"
        )
    }
    
    // 7. Safety Policy & Confirmation
    public static func testSafetyPolicyConfirmation() async -> TestResultReport {
        let executor = ToolExecutor()
        let dangerousTool = MockVerificationTool(
            id: "test.danger",
            name: "Delete All Items",
            riskLevel: .highRiskDestructive
        )
        
        // Attempt without confirmation
        let unconfirmed = await executor.execute(
            tool: dangerousTool,
            arguments: ToolArguments(["title": "All"]),
            context: ToolExecutionContext(isUserConfirmed: false)
        )
        let pass1 = (unconfirmed.status == .cancelled)
        
        // Attempt with confirmation
        let confirmed = await executor.execute(
            tool: dangerousTool,
            arguments: ToolArguments(["title": "All"]),
            context: ToolExecutionContext(isUserConfirmed: true)
        )
        let pass2 = (confirmed.status == .success)
        
        let allPass = pass1 && pass2
        return TestResultReport(
            testName: "Safety Policy & Confirmation",
            passed: allPass,
            detail: allPass ? "Blocked unconfirmed high-risk action, executed confirmed." : "Safety policy failure."
        )
    }
    
    // 8. Duplicate Execution Protection (Idempotency)
    public static func testDuplicateExecutionProtection() async -> TestResultReport {
        let executor = ToolExecutor()
        let tool = MockVerificationTool()
        let key = "unique-txn-\(UUID().uuidString)"
        
        let res1 = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Test"]),
            context: ToolExecutionContext(idempotencyKey: key)
        )
        let pass1 = (res1.status == .success)
        
        // Second execution with identical key must be blocked
        let res2 = await executor.execute(
            tool: tool,
            arguments: ToolArguments(["title": "Test"]),
            context: ToolExecutionContext(idempotencyKey: key)
        )
        let pass2 = (res2.status == .cancelled && res2.message.contains("Duplicate"))
        
        let allPass = pass1 && pass2
        return TestResultReport(
            testName: "Duplicate Execution Protection",
            passed: allPass,
            detail: allPass ? "Idempotency key blocked duplicate action execution." : "Duplicate action was not blocked."
        )
    }
    
    // 9. Generic Tool Router
    public static func testGenericToolRouter() async -> TestResultReport {
        let registry = ToolRegistry()
        let tool = MockVerificationTool(id: "test.router", name: "Create Reminder")
        registry.register(tool)
        
        let matched = GenericToolRouter.matchAndExtract(
            prompt: "tool: Create Reminder title: \"Buy Milk\"",
            from: registry
        )
        
        let pass = (matched != nil && matched?.arguments.string(for: "title") == "Buy Milk")
        return TestResultReport(
            testName: "Generic Tool Router",
            passed: pass,
            detail: pass ? "Matched tool from registry schema and extracted arguments." : "Router matching failed."
        )
    }
}
