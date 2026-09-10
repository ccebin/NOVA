import SwiftUI
import SwiftData
import UIKit

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    
    @State private var tempName: String = ""
    @State private var showingResetAlert: Bool = false
    @State private var showingExportSheet: Bool = false
    @State private var exportedJSON: String = ""
    @State private var storageStats: (conversationsCount: Int, messagesCount: Int) = (0, 0)
    @State private var showingToolTestsSheet: Bool = false
    @State private var testReports: [TestResultReport] = []
    @State private var agentLoopReports: [AgentLoopTestReport] = []
    @State private var phase5Reports: [Phase5TestReport] = []
    @State private var phase6Reports: [Phase6VoiceTestReport] = []
    @State private var phase7Reports: [Phase7RuntimeTestReport] = []
    @State private var phase8Reports: [Phase8TestReport] = []
    @State private var apiKeyInput: String = ""
    @State private var isEditingApiKey: Bool = false
    @State private var isRunningTests: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: Assistant Identity
                Section {
                    HStack {
                        Text("Assistant Name")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        TextField("Name", text: $tempName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(NovaTheme.accent)
                            .font(.system(size: 15, weight: .medium))
                            .onSubmit {
                                saveName()
                            }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("Identity")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("Configure your personal assistant's name. Defaults to NOVA.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 12))
                }
                
                // Section 2: AI Provider & Diagnostics
                Section {
                    Picker("Engine Selection", selection: Binding(
                        get: { appState.selectedEngine },
                        set: { appState.selectEngine($0) }
                    )) {
                        ForEach(ActiveEngineSelection.allCases) { engine in
                            Text(engine.title).tag(engine)
                        }
                    }
                    .foregroundColor(NovaTheme.ink)
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    Picker("Voice Pipeline", selection: Binding(
                        get: { appState.voicePolicy },
                        set: { appState.selectVoicePolicy($0) }
                    )) {
                        ForEach(VoiceRoutingPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .foregroundColor(NovaTheme.ink)
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Active Engine")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text(appState.activeProviderName)
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    if let notice = appState.fallbackNotice {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(NovaTheme.statusWarning)
                                .font(.system(size: 13))
                            Text(notice)
                                .font(.system(size: 12))
                                .foregroundColor(NovaTheme.statusWarning)
                        }
                        .listRowBackground(NovaTheme.statusWarning.opacity(0.1))
                    }
                    
                    NavigationLink(destination: CapabilitiesDetailView(report: appState.capabilitiesReport, smolProvider: appState.smolLM2Provider)) {
                        HStack {
                            Text("Capability Diagnostics")
                                .foregroundColor(NovaTheme.ink)
                                .font(.system(size: 15))
                            Spacer()
                            Circle()
                                .fill(appState.capabilitiesReport.isGenerativeAIAvailable ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    Button(action: {
                        appState.refreshCapabilities()
                    }) {
                        HStack {
                            Text("Re-scan System Capabilities")
                                .foregroundColor(NovaTheme.accent)
                                .font(.system(size: 15))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13))
                                .foregroundColor(NovaTheme.accent)
                        }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("Intelligence & Runtime")
                        .foregroundColor(NovaTheme.inkTertiary)
                }
                
                // Section 2.2: Google Gemini Free Tier & Secure Keychain Storage
                Section {
                    if appState.geminiKeyProvider.hasKey && !isEditingApiKey {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gemini API Key")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(NovaTheme.ink)
                                Text("Stored securely in iOS Keychain")
                                    .font(.system(size: 11))
                                    .foregroundColor(NovaTheme.inkTertiary)
                            }
                            Spacer()
                            Text(appState.geminiKeyProvider.maskedKey)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(NovaTheme.inkSecondary)
                        }
                        .listRowBackground(NovaTheme.surfaceCard)
                        
                        HStack {
                            Button("Update Key") {
                                isEditingApiKey = true
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(NovaTheme.accent)
                            
                            Spacer()
                            
                            Button("Delete Key") {
                                try? appState.geminiKeyProvider.deleteApiKey()
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                        }
                        .listRowBackground(NovaTheme.surfaceCard)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enter Google Gemini API Key")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(NovaTheme.ink)
                            
                            SecureField("Paste API key here...", text: $apiKeyInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(8)
                                .background(NovaTheme.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            HStack {
                                Button("Save to Keychain") {
                                    let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        try? appState.geminiKeyProvider.saveApiKey(trimmed)
                                        apiKeyInput = ""
                                        isEditingApiKey = false
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(NovaTheme.accent)
                                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                if isEditingApiKey {
                                    Spacer()
                                    Button("Cancel") {
                                        apiKeyInput = ""
                                        isEditingApiKey = false
                                    }
                                    .font(.system(size: 13))
                                    .foregroundColor(NovaTheme.inkTertiary)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(NovaTheme.surfaceCard)
                    }
                } header: {
                    Text("Google Gemini Free Tier (Phase 8)")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("Free Tier Only: gemini-3.8-flash (Text) and gemini-3.1-flash-live-preview (Voice). Zero automatic billing or paid plans. Secret keys are never stored in plaintext UserDefaults.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 11))
                }
                
                // Section 2.5: Verified Local Tools (Phase 3)
                Section {
                    ForEach(ToolRegistry.shared.allDefinitions()) { def in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(def.name)
                                    .foregroundColor(NovaTheme.ink)
                                    .font(.system(size: 14, weight: .medium))
                                Text(def.description)
                                    .foregroundColor(NovaTheme.inkTertiary)
                                    .font(.system(size: 11))
                            }
                            Spacer()
                            Text(def.riskLevel.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(NovaTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(NovaTheme.accentSubtle)
                                .clipShape(Capsule())
                        }
                        .listRowBackground(NovaTheme.surfaceCard)
                    }
                    
                    Button(action: runToolTests) {
                        HStack {
                            Text(isRunningTests ? "Running Verification..." : "Run Tool Verification Suite")
                                .foregroundColor(NovaTheme.statusGreen)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if isRunningTests {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(NovaTheme.statusGreen)
                            }
                        }
                    }
                    .disabled(isRunningTests)
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("Verified Local Tools (Phase 3)")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("Tools execute locally on iPhone via Apple's public EventKit APIs with mandatory state verification.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 12))
                }
                
                // Section 2.7: Native Voice & Audio Subsystem (Phase 6)
                Section {
                    HStack {
                        Text("Voice Engine Status")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.voiceManager.state == .idle ? NovaTheme.statusGreen : Color(red: 0.05, green: 0.70, blue: 1.00))
                                .frame(width: 7, height: 7)
                            Text(appState.voiceManager.state.displayName)
                                .foregroundColor(NovaTheme.inkSecondary)
                                .font(.system(size: 14))
                        }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    Picker("Voice Locale", selection: Binding(
                        get: { appState.voiceManager.voiceLocale },
                        set: { appState.voiceManager.voiceLocale = $0 }
                    )) {
                        Text("Device Default (\(Locale.current.identifier))").tag(Locale.current)
                        Text("Türkçe (tr-TR)").tag(Locale(identifier: "tr-TR"))
                        Text("English (en-US)").tag(Locale(identifier: "en-US"))
                    }
                    .foregroundColor(NovaTheme.ink)
                    .tint(NovaTheme.accent)
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Microphone Permission")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text(appState.capabilitiesReport.voiceCapabilities.microphonePermission.rawValue)
                            .foregroundColor(appState.capabilitiesReport.voiceCapabilities.microphonePermission == .granted ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Speech Recognition")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text(appState.capabilitiesReport.voiceCapabilities.speechRecognitionPermission.rawValue)
                            .foregroundColor(appState.capabilitiesReport.voiceCapabilities.speechRecognitionPermission == .granted ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("On-Device Dictation")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text(appState.capabilitiesReport.voiceCapabilities.offlineSpeechAvailable ? "Ready" : "Unavailable Locally")
                            .foregroundColor(appState.capabilitiesReport.voiceCapabilities.offlineSpeechAvailable ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("Native Voice & Audio (Phase 6)")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("NOVA utilizes local AVAudioEngine, SFSpeechRecognizer, and AVSpeechSynthesizer. Operates 100% offline.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 12))
                }
                
                // Section 3: Storage & Data Sovereignty
                Section {
                    HStack {
                        Text("Stored Conversations")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text("\(storageStats.conversationsCount)")
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Stored Messages")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text("\(storageStats.messagesCount)")
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    Button(action: handleExport) {
                        HStack {
                            Text("Export All Local Data (JSON)")
                                .foregroundColor(NovaTheme.accent)
                                .font(.system(size: 15))
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13))
                                .foregroundColor(NovaTheme.accent)
                        }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    Button(role: .destructive, action: { showingResetAlert = true }) {
                        HStack {
                            Text("Wipe Local Storage")
                                .foregroundColor(.red)
                                .font(.system(size: 15))
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("Local SwiftData Storage")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("All data is stored exclusively in your iPhone's sandboxed storage. No remote servers or cloud accounts are used.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 12))
                }
                
                // Section 4: Architecture
                Section {
                    HStack {
                        Text("Architecture")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text("Standalone iPhone Runtime")
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Target Environment")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text("Swift Playgrounds (iPad / iOS)")
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 14))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                    
                    HStack {
                        Text("Phase")
                            .foregroundColor(NovaTheme.ink)
                            .font(.system(size: 15))
                        Spacer()
                        Text("Phase 7: Real Single-Model On-Device LLM Runtime (SmolLM2-360M-Instruct)")
                            .foregroundColor(NovaTheme.inkSecondary)
                            .font(.system(size: 13))
                    }
                    .listRowBackground(NovaTheme.surfaceCard)
                } header: {
                    Text("System Info")
                        .foregroundColor(NovaTheme.inkTertiary)
                } footer: {
                    Text("Developed in Swift Playgrounds on iPad. Can be run inside Swift Playgrounds on iPhone for testing, or published as an independent standalone Home Screen app via App Store Connect / TestFlight without requiring a Mac.")
                        .foregroundColor(NovaTheme.inkTertiary)
                        .font(.system(size: 12))
                }
            }
            .scrollContentBackground(.hidden)
            .background(NovaTheme.canvas)
            .navigationTitle("Settings")
            .onAppear {
                tempName = appState.assistantName
                refreshStorageStats()
            }
            .confirmationDialog(
                "Wipe All Local Storage?",
                isPresented: $showingResetAlert,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    wipeStorage()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all conversations and messages stored in SwiftData.")
            }
            .sheet(isPresented: $showingExportSheet) {
                exportSheetView
            }
            .sheet(isPresented: $showingToolTestsSheet) {
                ToolTestsSheetView(
                    phase3Results: testReports,
                    phase4Results: agentLoopReports,
                    phase5Results: phase5Reports,
                    phase6Results: phase6Reports,
                    phase7Results: phase7Reports,
                    phase8Results: phase8Reports,
                    onRerun: runToolTests
                )
            }
        }
    }
    
    private func saveName() {
        let trimmed = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appState.assistantName = trimmed
        }
    }
    
    private func runToolTests() {
        isRunningTests = true
        Task {
            let p3 = await ToolSystemTests.runAllTests()
            let p4 = await AgentLoopTests.runAllTests()
            let p5 = await Phase5IntelligenceTests.runAllTests()
            let p6 = await Phase6VoiceTests.runAllTests()
            let p7 = await Phase7RuntimeTests.runAllTests()
            let p8 = await Phase8GeminiTests.runAllTests()
            self.testReports = p3
            self.agentLoopReports = p4
            self.phase5Reports = p5
            self.phase6Reports = p6
            self.phase7Reports = p7
            self.phase8Reports = p8
            self.isRunningTests = false
            self.showingToolTestsSheet = true
        }
    }
    
    private func refreshStorageStats() {
        let dm = LocalDataManager(modelContext: modelContext)
        storageStats = dm.getStorageStats()
    }
    
    private func wipeStorage() {
        let dm = LocalDataManager(modelContext: modelContext)
        dm.deleteAllConversations()
        appState.clearConversation(modelContext: modelContext)
        refreshStorageStats()
    }
    
    private func handleExport() {
        let dm = LocalDataManager(modelContext: modelContext)
        exportedJSON = dm.exportDataAsJSON()
        showingExportSheet = true
    }
    
    private var exportSheetView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Local Conversation Export (JSON)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(NovaTheme.ink)
                    .padding(.top, 16)
                
                ScrollView {
                    Text(exportedJSON)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(NovaTheme.inkSecondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NovaTheme.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                
                Button(action: {
                    UIPasteboard.general.string = exportedJSON
                    showingExportSheet = false
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to Clipboard")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NovaTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(NovaTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingExportSheet = false
                    }
                }
            }
        }
    }
}
