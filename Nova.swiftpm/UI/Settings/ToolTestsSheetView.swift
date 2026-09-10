import SwiftUI

public struct ToolTestsSheetView: View {
    public let phase3Results: [TestResultReport]
    public let phase4Results: [AgentLoopTestReport]
    public let phase5Results: [Phase5TestReport]
    public let phase6Results: [Phase6VoiceTestReport]
    public let phase7Results: [Phase7RuntimeTestReport]
    public let phase8Results: [Phase8TestReport]
    public let onRerun: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    public init(
        phase3Results: [TestResultReport],
        phase4Results: [AgentLoopTestReport] = [],
        phase5Results: [Phase5TestReport] = [],
        phase6Results: [Phase6VoiceTestReport] = [],
        phase7Results: [Phase7RuntimeTestReport] = [],
        phase8Results: [Phase8TestReport] = [],
        onRerun: @escaping () -> Void
    ) {
        self.phase3Results = phase3Results
        self.phase4Results = phase4Results
        self.phase5Results = phase5Results
        self.phase6Results = phase6Results
        self.phase7Results = phase7Results
        self.phase8Results = phase8Results
        self.onRerun = onRerun
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Header Summary Card
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOVA Verification Suites")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(NovaTheme.ink)
                            Text("\(totalPassed) of \(totalRunnable) Runnable Tests Passed")
                                .font(.system(size: 13))
                                .foregroundColor(totalPassed == totalRunnable ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                        }
                        Spacer()
                        Button(action: onRerun) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(NovaTheme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(NovaTheme.surfaceCard)
                }
                
                // Section: Phase 8 — Gemini 3.8 Flash, Gemini Live & Free Tier Routing
                if !phase8Results.isEmpty {
                    let catA = phase8Results.filter { $0.category == .categoryA }
                    let catB = phase8Results.filter { $0.category == .categoryB }
                    let catC = phase8Results.filter { $0.category == .categoryC }
                    let catD = phase8Results.filter { $0.category == .categoryD }
                    let catE = phase8Results.filter { $0.category == .categoryE }
                    
                    Section("Phase 8 — Category A: REST & Free Tier Normalization") {
                        ForEach(catA) { report in
                            phase8Row(report)
                        }
                    }
                    
                    Section("Phase 8 — Category B: ONE NOVA Routing & Invariance") {
                        ForEach(catB) { report in
                            phase8Row(report)
                        }
                    }
                    
                    Section("Phase 8 — Category C: Tool Execution & Verification Gate") {
                        ForEach(catC) { report in
                            phase8Row(report)
                        }
                    }
                    
                    Section("Phase 8 — Category D: Gemini Live WebSocket & Audio Specs") {
                        ForEach(catD) { report in
                            phase8Row(report)
                        }
                    }
                    
                    Section("Phase 8 — Category E: Security & Turkish UTF-8") {
                        ForEach(catE) { report in
                            phase8Row(report)
                        }
                    }
                }
                
                // Section: Phase 7 — Real Single-Model On-Device Intelligence Runtime
                if !phase7Results.isEmpty {
                    let catA = phase7Results.filter { $0.category == .categoryA }
                    let catB = phase7Results.filter { $0.category == .categoryB }
                    let catC = phase7Results.filter { $0.category == .categoryC }
                    
                    Section("Phase 7 — Category A: Deterministic Unit Tests") {
                        ForEach(catA) { report in
                            phase7Row(report)
                        }
                    }
                    
                    Section("Phase 7 — Category B: Single-Model Pipeline Integration") {
                        ForEach(catB) { report in
                            phase7Row(report)
                        }
                    }
                    
                    Section("Phase 7 — Category C: Real Device Verification & Benchmarks") {
                        ForEach(catC) { report in
                            phase7Row(report)
                        }
                    }
                }
                
                // Section: Phase 6 — Native Voice & Conversational Audio
                if !phase6Results.isEmpty {
                    let catA = phase6Results.filter { $0.category == .categoryA }
                    let catB = phase6Results.filter { $0.category == .categoryB }
                    let catC = phase6Results.filter { $0.category == .categoryC }
                    
                    Section("Phase 6 — Category A: Voice Infrastructure") {
                        ForEach(catA) { report in
                            phase6Row(report)
                        }
                    }
                    
                    Section("Phase 6 — Category B: Mock-Audio Integration") {
                        ForEach(catB) { report in
                            phase6Row(report)
                        }
                    }
                    
                    Section("Phase 6 — Category C: Real Device Tests") {
                        ForEach(catC) { report in
                            phase6Row(report)
                        }
                    }
                }
                
                // Section: Phase 5 — Intelligence, Personality & Memory Core
                if !phase5Results.isEmpty {
                    let catA = phase5Results.filter { $0.category == .categoryA }
                    let catB = phase5Results.filter { $0.category == .categoryB }
                    let catC = phase5Results.filter { $0.category == .categoryC }
                    
                    Section("Phase 5 — Category A: Intelligence Infrastructure") {
                        ForEach(catA) { report in
                            phase5Row(report)
                        }
                    }
                    
                    Section("Phase 5 — Category B: Mock-Provider Integration") {
                        ForEach(catB) { report in
                            phase5Row(report)
                        }
                    }
                    
                    Section("Phase 5 — Category C: Device Diagnostics") {
                        ForEach(catC) { report in
                            phase5Row(report)
                        }
                    }
                }
                
                // Section: Phase 4 — Unified Agent Loop
                if !phase4Results.isEmpty {
                    Section("Phase 4 — Unified Agent Loop Tests") {
                        ForEach(phase4Results) { report in
                            agentLoopRow(report)
                        }
                    }
                }
                
                // Section: Phase 3 — Verified Local Tools
                Section("Phase 3 — Verified Local Tools Tests") {
                    ForEach(phase3Results) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                                    .font(.system(size: 14))
                                
                                Text(report.testName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(NovaTheme.ink)
                                
                                Spacer()
                                
                                Text(report.passed ? "PASS" : "FAIL")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                            }
                            
                            Text(report.detail)
                                .font(.system(size: 12))
                                .foregroundColor(NovaTheme.inkSecondary)
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(NovaTheme.surfaceCard)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NovaTheme.canvas)
            .navigationTitle("Verification Suites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(NovaTheme.accent)
                }
            }
        }
    }
    
    private func phase8Row(_ report: Phase8TestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                    .font(.system(size: 14))
                
                Text(report.testName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                Text(report.passed ? "PASS" : "FAIL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
            }
            
            Text(report.detail)
                .font(.system(size: 11))
                .foregroundColor(NovaTheme.inkSecondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private func phase5Row(_ report: Phase5TestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if report.isSDKUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NovaTheme.statusWarning)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                        .font(.system(size: 14))
                }
                
                Text(report.testName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                if report.isSDKUnavailable {
                    Text("NOT TESTABLE IN SDK")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.statusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NovaTheme.statusWarning.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Text(report.passed ? "PASS" : "FAIL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                }
            }
            
            Text(report.detail)
                .font(.system(size: 11))
                .foregroundColor(NovaTheme.inkSecondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private func phase6Row(_ report: Phase6VoiceTestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if report.isRealDeviceOnly {
                    Image(systemName: "iphone")
                        .foregroundColor(NovaTheme.statusWarning)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                        .font(.system(size: 14))
                }
                
                Text(report.testName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                if report.isRealDeviceOnly {
                    Text("REAL DEVICE REQUIRED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.statusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NovaTheme.statusWarning.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Text(report.passed ? "PASS" : "FAIL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                }
            }
            
            Text(report.detail)
                .font(.system(size: 11))
                .foregroundColor(NovaTheme.inkSecondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private func agentLoopRow(_ report: AgentLoopTestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if report.isSDKUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(NovaTheme.statusWarning)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                        .font(.system(size: 14))
                }
                
                Text(report.testName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                if report.isSDKUnavailable {
                    Text("NOT TESTABLE IN SDK")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.statusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NovaTheme.statusWarning.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Text(report.passed ? "PASS" : "FAIL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                }
            }
            
            Text(report.detail)
                .font(.system(size: 11))
                .foregroundColor(NovaTheme.inkSecondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private func phase7Row(_ report: Phase7RuntimeTestReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if report.isRealDeviceOnly {
                    Image(systemName: "iphone")
                        .foregroundColor(NovaTheme.statusWarning)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: report.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                        .font(.system(size: 14))
                }
                
                Text(report.testName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                
                Spacer()
                
                if report.isRealDeviceOnly {
                    Text("REAL DEVICE REQUIRED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.statusWarning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NovaTheme.statusWarning.opacity(0.15))
                        .clipShape(Capsule())
                } else {
                    Text(report.passed ? "PASS" : "FAIL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(report.passed ? NovaTheme.statusGreen : Color.red)
                }
            }
            
            Text(report.detail)
                .font(.system(size: 11))
                .foregroundColor(NovaTheme.inkSecondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private var totalPassed: Int {
        let p3 = phase3Results.filter { $0.passed }.count
        let p4 = phase4Results.filter { $0.passed }.count
        let p5 = phase5Results.filter { $0.passed }.count
        let p6 = phase6Results.filter { $0.passed }.count
        let p7 = phase7Results.filter { $0.passed }.count
        let p8 = phase8Results.filter { $0.passed }.count
        return p3 + p4 + p5 + p6 + p7 + p8
    }
    
    private var totalRunnable: Int {
        let p3 = phase3Results.count
        let p4 = phase4Results.filter { !$0.isSDKUnavailable }.count
        let p5 = phase5Results.filter { !$0.isSDKUnavailable }.count
        let p6 = phase6Results.filter { !$0.isRealDeviceOnly }.count
        let p7 = phase7Results.filter { !$0.isRealDeviceOnly }.count
        let p8 = phase8Results.count
        return p3 + p4 + p5 + p6 + p7 + p8
    }
}
