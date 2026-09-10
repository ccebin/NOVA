import SwiftUI

public struct CapabilitiesDetailView: View {
    public let report: SystemCapabilitiesReport
    public let smolProvider: SmolLM2Provider?
    
    public init(report: SystemCapabilitiesReport, smolProvider: SmolLM2Provider? = nil) {
        self.report = report
        self.smolProvider = smolProvider
    }
    
    public var body: some View {
        List {
            // Section 1: Summary Status
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(report.isGenerativeAIAvailable ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                            .frame(width: 10, height: 10)
                        Text(report.userFacingSummary)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(NovaTheme.ink)
                    }
                    
                    Text("NOVA reports device hardware, operating system, and SDK capabilities factually without arbitrary thresholds or guessed private classes.")
                        .font(.system(size: 13))
                        .foregroundColor(NovaTheme.inkSecondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(NovaTheme.surfaceCard)
            } header: {
                Text("Overall Diagnostic")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 2: Operating System
            Section {
                diagnosticRow(
                    title: "iOS Version",
                    value: report.osCapability.osVersionString,
                    isPass: report.osCapability.majorVersion >= 17,
                    note: "Host operating system version."
                )
            } header: {
                Text("Operating System")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 3: Hardware
            Section {
                diagnosticRow(
                    title: "Device Model",
                    value: report.hardwareCapability.deviceModelIdentifier,
                    isPass: true,
                    note: nil
                )
                diagnosticRow(
                    title: "Physical Memory",
                    value: String(format: "%.1f GB", report.hardwareCapability.physicalMemoryGB),
                    isPass: true,
                    note: "Informational diagnostic data reported by ProcessInfo."
                )
            } header: {
                Text("Hardware Diagnostics")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 4: Apple Intelligence
            Section {
                diagnosticRow(
                    title: "Apple Intelligence",
                    value: report.appleIntelligenceCapability.status.rawValue,
                    isPass: report.appleIntelligenceCapability.status == .systemManaged,
                    note: report.appleIntelligenceCapability.detail
                )
            } header: {
                Text("Apple Intelligence Status")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 5: Foundation Models Framework
            Section {
                diagnosticRow(
                    title: "Public Generative SDK",
                    value: report.foundationModelsCapability.status.rawValue,
                    isPass: report.foundationModelsCapability.isAvailable,
                    note: report.foundationModelsCapability.explanation
                )
            } header: {
                Text("Foundation Models Runtime")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 5B: On-Device Single Model Runtime (SmolLM2-360M-Instruct)
            Section {
                let smol = smolProvider ?? SmolLM2Provider()
                
                diagnosticRow(
                    title: "Provider Selected",
                    value: smol.displayName,
                    isPass: true,
                    note: "Explicit on-device LLM provider (ID: \(smol.id))."
                )
                diagnosticRow(
                    title: "Model Status",
                    value: smol.detailedStatus.rawValue,
                    isPass: smol.detailedStatus == .modelReady,
                    note: "Exact lifecycle state of the SmolLM2 runtime."
                )
                diagnosticRow(
                    title: "Model Discovered",
                    value: smol.isModelArtifactPresent ? "Yes" : "No",
                    isPass: smol.isModelArtifactPresent,
                    note: smol.isModelArtifactPresent ? "Artifact verified on local filesystem." : "Weights missing from disk."
                )
                diagnosticRow(
                    title: "Model Compiled",
                    value: smol.isModelArtifactPresent ? "Compiled (.mlmodelc)" : "Not Present",
                    isPass: smol.isModelArtifactPresent,
                    note: "Core ML compiled model artifact: \(SmolLM2Contract.compiledModelName)."
                )
                diagnosticRow(
                    title: "Model Loaded",
                    value: smol.isModelLoaded ? "Loaded in Memory" : "Standby (Not Loaded)",
                    isPass: smol.isModelLoaded,
                    note: "Loaded on demand during first inference to preserve resident memory."
                )
                diagnosticRow(
                    title: "Model Path",
                    value: smol.resolvedModelPath ?? "Documents/Models/\(SmolLM2Contract.compiledModelName)",
                    isPass: smol.isModelArtifactPresent,
                    note: smol.resolvedModelPath != nil ? "Active filesystem resolution path." : "Expected placement directory."
                )
                diagnosticRow(
                    title: "Core ML Availability",
                    value: {
                        #if canImport(CoreML)
                        return "Available"
                        #else
                        return "NOT_VERIFIABLE_ON_CURRENT_HOST"
                        #endif
                    }(),
                    isPass: {
                        #if canImport(CoreML)
                        return true
                        #else
                        return false
                        #endif
                    }(),
                    note: "Host operating system Core ML framework capability."
                )
                diagnosticRow(
                    title: "Stateful MLProgram",
                    value: report.osCapability.majorVersion >= 18 ? "Supported (iOS 18+)" : "Requires iOS 18.0+",
                    isPass: report.osCapability.majorVersion >= 18,
                    note: "Required by Core ML 8 stateful MLState operations."
                )
                diagnosticRow(
                    title: "Required OS Version",
                    value: "iOS 18.0+ / macOS 15.0+",
                    isPass: report.osCapability.majorVersion >= 18,
                    note: "Minimum Apple OS version for SmolLM2 Core ML execution."
                )
                diagnosticRow(
                    title: "Theoretical KV Footprint",
                    value: "83.8 MB (Buffer Only)",
                    isPass: true,
                    note: "Theoretical KV-cache calculation: 32L * 2 * (1*5*2048*64) * 2B. Does NOT include weights (~203.7 MB) or framework RAM."
                )
                diagnosticRow(
                    title: "Last Inference Status",
                    value: smol.lastInferenceStatus,
                    isPass: smol.detailedStatus != .inferenceFailed,
                    note: "Status string from last execution attempt."
                )
                diagnosticRow(
                    title: "Live Hardware Metrics",
                    value: "NOT_VERIFIABLE_ON_CURRENT_HOST",
                    isPass: false,
                    note: "Real TTFT, tokens/sec, resident RAM, and thermal state require physical iPhone execution."
                )
            } header: {
                Text("On-Device LLM Runtime (SmolLM2-360M-Instruct)")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 6: Native Voice & Audio Subsystem
            Section {
                diagnosticRow(
                    title: "Microphone Hardware",
                    value: report.voiceCapabilities.microphoneAvailable ? "Available" : "Not Detected",
                    isPass: report.voiceCapabilities.microphoneAvailable,
                    note: "Detected via AVAudioSession input route."
                )
                diagnosticRow(
                    title: "Microphone Permission",
                    value: report.voiceCapabilities.microphonePermission.rawValue,
                    isPass: report.voiceCapabilities.microphonePermission == .granted,
                    note: "System record permission."
                )
                diagnosticRow(
                    title: "Speech Recognition Service",
                    value: report.voiceCapabilities.speechRecognitionAvailable ? "Available" : "Unavailable",
                    isPass: report.voiceCapabilities.speechRecognitionAvailable,
                    note: "Apple SFSpeechRecognizer availability."
                )
                diagnosticRow(
                    title: "Speech Permission",
                    value: report.voiceCapabilities.speechRecognitionPermission.rawValue,
                    isPass: report.voiceCapabilities.speechRecognitionPermission == .granted,
                    note: "System speech recognition authorization."
                )
                diagnosticRow(
                    title: "Offline Speech Recognition",
                    value: report.voiceCapabilities.offlineSpeechAvailable ? "On-Device Ready" : "Unavailable Locally",
                    isPass: report.voiceCapabilities.offlineSpeechAvailable,
                    note: report.voiceCapabilities.offlineSpeechAvailable
                        ? "Apple SFSpeechRecognizer supports on-device offline recognition for this locale."
                        : "Requires local dictation assets in iOS Settings."
                )
                diagnosticRow(
                    title: "Speech Synthesis (TTS)",
                    value: report.voiceCapabilities.speechSynthesisAvailable ? "Available" : "Unavailable",
                    isPass: report.voiceCapabilities.speechSynthesisAvailable,
                    note: "Apple AVSpeechSynthesizer offline voices."
                )
                diagnosticRow(
                    title: "Active Voice Locale",
                    value: report.voiceCapabilities.selectedVoiceLocale,
                    isPass: report.voiceCapabilities.selectedVoiceAvailable,
                    note: "Locale used for recognition and speech output."
                )
            } header: {
                Text("Native Voice & Audio Capabilities")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
            
            // Section 7: Network & Privacy
            Section {
                diagnosticRow(
                    title: "Network Mode",
                    value: "Offline (Zero-Network)",
                    isPass: true,
                    note: "Wi-Fi and Cellular are not used. The application operates entirely standalone."
                )
                diagnosticRow(
                    title: "External Server",
                    value: "None",
                    isPass: true,
                    note: "No external computer, local network runner, server, or cloud AI connected."
                )
            } header: {
                Text("Privacy & Network Isolation")
                    .foregroundColor(NovaTheme.inkTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NovaTheme.canvas)
        .navigationTitle("System Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func diagnosticRow(title: String, value: String, isPass: Bool, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NovaTheme.ink)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(isPass ? NovaTheme.statusGreen : NovaTheme.statusWarning)
                        .frame(width: 6, height: 6)
                    Text(value)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(NovaTheme.inkSecondary)
                }
            }
            
            if let note = note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.inkTertiary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(NovaTheme.surfaceCard)
    }
}
