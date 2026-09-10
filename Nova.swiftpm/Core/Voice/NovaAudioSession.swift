import Foundation
import AVFoundation

/// Manages the system AVAudioSession lifecycle, categories, route changes, interruptions, and microphone permissions.
public final class NovaAudioSession: @unchecked Sendable {
    public static let shared = NovaAudioSession()
    
    private let session = AVAudioSession.sharedInstance()
    private var isConfigured: Bool = false
    private var isActive: Bool = false
    
    // Callbacks for interruptions and route adjustments
    public var onInterruptionBegan: (@Sendable () -> Void)?
    public var onInterruptionEnded: (@Sendable (_ shouldResume: Bool) -> Void)?
    public var onRouteChange: (@Sendable (_ reason: AVAudioSession.RouteChangeReason) -> Void)?
    public var onMediaServicesReset: (@Sendable () -> Void)?
    
    public init() {
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Permission Handling
    
    public func microphonePermissionStatus() -> VoicePermissionStatus {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        } else {
            switch session.recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        }
        #else
        return .granted
        #endif
    }
    
    public func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        return true
        #endif
    }
    
    // MARK: - Configuration & Activation
    
    public func configureSession() throws {
        guard !isConfigured else { return }
        do {
            #if os(iOS)
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            #endif
            isConfigured = true
        } catch {
            throw NovaVoiceError.audioSessionFailed(reason: error.localizedDescription)
        }
    }
    
    public func activate() throws {
        try configureSession()
        guard !isActive else { return }
        do {
            #if os(iOS)
            try session.setActive(true, options: [])
            #endif
            isActive = true
        } catch {
            throw NovaVoiceError.audioSessionFailed(reason: error.localizedDescription)
        }
    }
    
    public func deactivate(notifyOthers: Bool = true) {
        guard isActive else { return }
        do {
            #if os(iOS)
            let options: AVAudioSession.SetActiveOptions = notifyOthers ? [.notifyOthersOnDeactivation] : []
            try session.setActive(false, options: options)
            #endif
            isActive = false
        } catch {
            // Non-fatal deactivation error logging
            isActive = false
        }
    }
    
    public var isInputAvailable: Bool {
        #if os(iOS)
        return session.isInputAvailable
        #else
        return true
        #endif
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        #if os(iOS)
        let center = NotificationCenter.default
        
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }
        
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification: notification)
        }
        
        center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isConfigured = false
            self?.isActive = false
            self?.onMediaServicesReset?()
        }
        #endif
    }
    
    #if os(iOS)
    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch interruptionType {
        case .began:
            isActive = false
            onInterruptionBegan?()
        case .ended:
            var shouldResume = false
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        onRouteChange?(reason)
    }
    #endif
}
