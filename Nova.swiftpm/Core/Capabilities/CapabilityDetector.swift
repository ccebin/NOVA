import Foundation
import UIKit
import AVFoundation
import Speech

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct SystemCapabilitiesReport: Sendable {
    public let osCapability: OSCapability
    public let hardwareCapability: HardwareCapability
    public let appleIntelligenceCapability: AppleIntelligenceCapability
    public let foundationModelsCapability: FoundationModelsCapability
    public let voiceCapabilities: VoiceCapabilities
    
    public var isGenerativeAIAvailable: Bool {
        foundationModelsCapability.isAvailable
    }
    
    public var userFacingSummary: String {
        switch foundationModelsCapability.status {
        case .available:
            return "On-Device Apple Foundation Model Ready"
        case .deviceNotEligible:
            return "Device Ineligible for Foundation Models"
        case .modelNotReady:
            return "Foundation Model Not Ready / Downloading Assets"
        case .appleIntelligenceDisabled:
            return "Apple Intelligence Disabled in System Settings"
        case .sdkUnavailable:
            return "FoundationModels Framework Not Present in Current SDK"
        case .unavailable:
            return "Foundation Model Unavailable"
        }
    }
}

public struct OSCapability: Sendable {
    public let osVersionString: String
    public let majorVersion: Int
    public let minorVersion: Int
    public let patchVersion: Int
}

public struct HardwareCapability: Sendable {
    public let deviceModelIdentifier: String
    public let physicalMemoryBytes: UInt64
    public let physicalMemoryGB: Double
}

public struct AppleIntelligenceCapability: Sendable {
    public enum Status: String, Sendable {
        case available = "Available"
        case systemManaged = "System Managed"
        case unsupportedOS = "Requires iOS 18+"
    }
    
    public let status: Status
    public let detail: String
}

public struct FoundationModelsCapability: Sendable {
    public enum Status: String, Sendable {
        case available = "Available"
        case deviceNotEligible = "Device Hardware Ineligible"
        case modelNotReady = "Model Not Ready / Pending Download"
        case appleIntelligenceDisabled = "Apple Intelligence Disabled"
        case sdkUnavailable = "SDK Framework Unavailable"
        case unavailable = "Unavailable"
    }
    
    public let isAvailable: Bool
    public let status: Status
    public let explanation: String
}

public enum VoicePermissionStatus: String, Sendable {
    case undetermined = "Not Determined"
    case granted = "Granted"
    case denied = "Denied"
    case restricted = "Restricted"
}

public struct VoiceCapabilities: Sendable {
    public let microphoneAvailable: Bool
    public let microphonePermission: VoicePermissionStatus
    public let speechRecognitionAvailable: Bool
    public let speechRecognitionPermission: VoicePermissionStatus
    public let offlineSpeechAvailable: Bool
    public let speechSynthesisAvailable: Bool
    public let selectedVoiceAvailable: Bool
    public let selectedVoiceLocale: String
    
    public init(
        microphoneAvailable: Bool,
        microphonePermission: VoicePermissionStatus,
        speechRecognitionAvailable: Bool,
        speechRecognitionPermission: VoicePermissionStatus,
        offlineSpeechAvailable: Bool,
        speechSynthesisAvailable: Bool,
        selectedVoiceAvailable: Bool,
        selectedVoiceLocale: String
    ) {
        self.microphoneAvailable = microphoneAvailable
        self.microphonePermission = microphonePermission
        self.speechRecognitionAvailable = speechRecognitionAvailable
        self.speechRecognitionPermission = speechRecognitionPermission
        self.offlineSpeechAvailable = offlineSpeechAvailable
        self.speechSynthesisAvailable = speechSynthesisAvailable
        self.selectedVoiceAvailable = selectedVoiceAvailable
        self.selectedVoiceLocale = selectedVoiceLocale
    }
}

public final class CapabilityDetector: Sendable {
    public static let shared = CapabilityDetector()
    
    public init() {}
    
    public func detectCapabilities() -> SystemCapabilitiesReport {
        let os = detectOS()
        let hardware = detectHardware()
        let appleIntel = detectAppleIntelligence(os: os)
        let foundation = detectFoundationModels()
        let voice = detectVoice()
        
        return SystemCapabilitiesReport(
            osCapability: os,
            hardwareCapability: hardware,
            appleIntelligenceCapability: appleIntel,
            foundationModelsCapability: foundation,
            voiceCapabilities: voice
        )
    }
    
    private func detectOS() -> OSCapability {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionStr = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        
        return OSCapability(
            osVersionString: versionStr,
            majorVersion: version.majorVersion,
            minorVersion: version.minorVersion,
            patchVersion: version.patchVersion
        )
    }
    
    private func detectHardware() -> HardwareCapability {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        let memBytes = ProcessInfo.processInfo.physicalMemory
        let memGB = Double(memBytes) / (1024.0 * 1024.0 * 1024.0)
        
        return HardwareCapability(
            deviceModelIdentifier: identifier.isEmpty ? "iOS Device" : identifier,
            physicalMemoryBytes: memBytes,
            physicalMemoryGB: memGB
        )
    }
    
    private func detectAppleIntelligence(os: OSCapability) -> AppleIntelligenceCapability {
        if os.majorVersion < 18 {
            return AppleIntelligenceCapability(
                status: .unsupportedOS,
                detail: "Current OS is iOS \(os.osVersionString). Apple Intelligence requires iOS 18 or newer."
            )
        }
        
        return AppleIntelligenceCapability(
            status: .systemManaged,
            detail: "Apple Intelligence features are present at system level."
        )
    }
    
    private func detectFoundationModels() -> FoundationModelsCapability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return FoundationModelsCapability(
                isAvailable: true,
                status: .available,
                explanation: "Apple SystemLanguageModel is available and ready for on-device generation."
            )
        case .unavailable(.deviceNotEligible):
            return FoundationModelsCapability(
                isAvailable: false,
                status: .deviceNotEligible,
                explanation: "Device hardware is not eligible for on-device Apple Foundation Models."
            )
        case .unavailable(.modelNotReady):
            return FoundationModelsCapability(
                isAvailable: false,
                status: .modelNotReady,
                explanation: "On-device model assets are pending download or not ready."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return FoundationModelsCapability(
                isAvailable: false,
                status: .appleIntelligenceDisabled,
                explanation: "Apple Intelligence is disabled in iOS System Settings."
            )
        case .unavailable(let reason):
            return FoundationModelsCapability(
                isAvailable: false,
                status: .unavailable,
                explanation: "Foundation Model unavailable: \(reason)"
            )
        }
        #else
        return FoundationModelsCapability(
            isAvailable: false,
            status: .sdkUnavailable,
            explanation: "The FoundationModels framework is not available in the current SDK build. Requires iOS 26+ SDK."
        )
        #endif
    }
    
    private func detectVoice() -> VoiceCapabilities {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let micAvail = session.isInputAvailable
        
        let micPerm: VoicePermissionStatus
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: micPerm = .granted
            case .denied: micPerm = .denied
            case .undetermined: micPerm = .undetermined
            @unknown default: micPerm = .undetermined
            }
        } else {
            switch session.recordPermission {
            case .granted: micPerm = .granted
            case .denied: micPerm = .denied
            case .undetermined: micPerm = .undetermined
            @unknown default: micPerm = .undetermined
            }
        }
        
        let speechPerm: VoicePermissionStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechPerm = .granted
        case .denied: speechPerm = .denied
        case .restricted: speechPerm = .restricted
        case .notDetermined: speechPerm = .undetermined
        @unknown default: speechPerm = .undetermined
        }
        
        let currentLocale = Locale.current
        let recognizer = SFSpeechRecognizer(locale: currentLocale)
        let speechAvail = recognizer?.isAvailable ?? false
        let offlineAvail = recognizer?.supportsOnDeviceRecognition ?? false
        
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let ttsAvail = !voices.isEmpty
        let selectedVoiceAvail = AVSpeechSynthesisVoice(language: currentLocale.identifier) != nil || AVSpeechSynthesisVoice(language: "en-US") != nil
        
        return VoiceCapabilities(
            microphoneAvailable: micAvail,
            microphonePermission: micPerm,
            speechRecognitionAvailable: speechAvail,
            speechRecognitionPermission: speechPerm,
            offlineSpeechAvailable: offlineAvail,
            speechSynthesisAvailable: ttsAvail,
            selectedVoiceAvailable: selectedVoiceAvail,
            selectedVoiceLocale: currentLocale.identifier
        )
        #else
        return VoiceCapabilities(
            microphoneAvailable: true,
            microphonePermission: .granted,
            speechRecognitionAvailable: true,
            speechRecognitionPermission: .granted,
            offlineSpeechAvailable: true,
            speechSynthesisAvailable: true,
            selectedVoiceAvailable: true,
            selectedVoiceLocale: Locale.current.identifier
        )
        #endif
    }
}
