// Permissions.swift — Check, request, and explain macOS privacy permissions
@preconcurrency import ApplicationServices
import AVFoundation
import AppKit
import SMCKit
import ServiceManagement
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "permissions")

public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case inputMonitoring
    case accessibility
    case screenRecording
    case camera
    case microphone
    case helper
    case automation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .helper: return "Background Helper"
        case .automation: return "Automation"
        }
    }

    /// Short reason shown in Settings so the user knows why Macotron asks.
    public var reason: String {
        switch self {
        case .inputMonitoring: return "Snippet expansion, window snap, and event taps."
        case .accessibility: return "Move and focus windows from plugins."
        case .screenRecording: return "Capture the screen for plugins that read it."
        case .camera: return "Scan a QR code or use the camera from a plugin."
        case .microphone: return "Record audio from plugins."
        case .helper: return "Lets plugins control privileged features like fan control."
        case .automation: return "Control other apps through Apple events."
        }
    }

    @MainActor
    public var isGranted: Bool {
        switch self {
        case .accessibility:
            return AXIsProcessTrusted()
        case .inputMonitoring:
            return Permissions.isInputMonitoringGranted
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .camera:
            return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .helper:
            return Permissions.helperService.status == .enabled
        case .automation:
            return true
        }
    }

    /// Title of the row action. The background helper installs a daemon instead of
    /// asking macOS for access, so it does not read as granting anything.
    public var actionTitle: String {
        switch self {
        case .inputMonitoring, .accessibility, .screenRecording, .camera, .microphone: return "Grant…"
        case .helper: return "Install…"
        case .automation: return "Open Settings…"
        }
    }

    /// A TCC permission request is a no-op once macOS has shown its dialog, so
    /// it is safe to fire on launch. Registering a root daemon is not: it asks
    /// for admin approval, so it needs an explicit user gesture behind it.
    public var isAutoRequestable: Bool {
        switch self {
        case .inputMonitoring, .accessibility, .screenRecording, .camera, .microphone: return true
        case .helper, .automation: return false
        }
    }

    /// TCC permissions can only be turned off in System Settings; the helper
    /// is ours to unregister.
    public var canRevoke: Bool {
        switch self {
        case .inputMonitoring, .accessibility, .screenRecording, .camera, .microphone, .automation: return false
        case .helper: return true
        }
    }

    /// Ask macOS for the permission. This also registers Macotron in the
    /// matching System Settings list, so the user can find the toggle.
    /// Returns whether to open System Settings after the request.
    @MainActor
    @discardableResult
    public func request() -> Bool {
        let openSettings: Bool
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            openSettings = true
        case .inputMonitoring:
            Permissions.requestInputMonitoring()
            openSettings = true
        case .screenRecording:
            CGRequestScreenCaptureAccess()
            openSettings = true
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            openSettings = true
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            openSettings = true
        case .helper:
            openSettings = Permissions.registerHelper()
        case .automation:
            openSettings = true
        }
        return openSettings
    }

    @MainActor
    public func revoke() {
        switch self {
        case .inputMonitoring, .accessibility, .screenRecording, .camera, .microphone, .automation:
            break
        case .helper:
            Permissions.unregisterHelper()
        }
    }

    @MainActor
    public func openSystemSettings() {
        let urlString: String
        switch self {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .camera:
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"
        case .helper:
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case .automation:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
public enum Permissions {
    /// Always required, whether or not any plugin is installed.
    public static let baseline: [Permission] = [.inputMonitoring, .accessibility, .automation]

    /// Map a plugin declaration string to a permission.
    public static func parse(_ name: String) -> Permission? {
        switch name.lowercased() {
        case "inputmonitoring", "input-monitoring", "keyboard", "hotkeys":
            return .inputMonitoring
        case "accessibility", "window", "windows":
            return .accessibility
        case "screenrecording", "screen-recording", "screen", "screencapture":
            return .screenRecording
        case "camera", "webcam", "qr":
            return .camera
        case "microphone", "mic":
            return .microphone
        case "helper":
            return .helper
        case "automation", "appleevents", "apple-events":
            return .automation
        default:
            return nil
        }
    }

    /// Baseline plus whatever the loaded plugins declared, in a stable order.
    public static func required(declaredBy plugins: Set<String>) -> [Permission] {
        let declared = plugins.compactMap(parse)
        return Permission.allCases.filter { baseline.contains($0) || declared.contains($0) }
    }

    public static func missing(from required: [Permission]) -> [Permission] {
        required.filter { !$0.isGranted }
    }

    /// Ask for every required permission that is still missing. macOS only shows
    /// its own dialog once per permission, but the request always registers the
    /// app in the System Settings list. Capabilities that install something are
    /// skipped here — those wait for the user to select the button.
    public static func registerWithSystem(_ required: [Permission]) {
        for permission in missing(from: required) where permission.isAutoRequestable {
            permission.request()
        }
    }

    // MARK: - Privileged helper daemon

    static var helperService: SMAppService {
        SMAppService.daemon(plistName: MacotronHelperService.plistName)
    }

    /// Let the helper's capabilities wind down before launchd tears it apart.
    public static var beforeHelperUnregister: (() -> Void)?

    /// The daemon lands in Login Items & Extensions switched off, so
    /// `.requiresApproval` is the expected outcome of the first registration.
    /// Returns true when Settings should open so the user can approve it.
    static func registerHelper() -> Bool {
        let service = helperService
        if service.status == .enabled { return false }
        do {
            try service.register()
        } catch {
            if service.status != .requiresApproval {
                logger.error("Helper registration failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "Could not install the background helper"
                alert.informativeText = error.localizedDescription
                    + "\n\nSign Macotron with a Developer ID, then try Install again."
                alert.runModal()
                return false
            }
        }
        return service.status != .enabled
    }

    static func unregisterHelper() {
        beforeHelperUnregister?()
        do {
            try helperService.unregister()
        } catch {
            logger.error("Helper removal failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Input Monitoring internals

    static var isInputMonitoringGranted: Bool {
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDCheckAccessFunc = @convention(c) (UInt32) -> UInt32
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "IOHIDCheckAccess") {
            let check = unsafeBitCast(sym, to: IOHIDCheckAccessFunc.self)
            return check(kIOHIDRequestTypeListenEvent) == 0
        }

        // Fallback for pre-Sequoia: try creating a passive event tap.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    /// IOHIDRequestAccess shows a one-shot dialog and registers the app in the
    /// Input Monitoring list. It does not open System Settings on its own.
    static func requestInputMonitoring() {
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDRequestAccessFunc = @convention(c) (UInt32) -> Bool
        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "IOHIDRequestAccess") else { return }
        let request = unsafeBitCast(sym, to: IOHIDRequestAccessFunc.self)
        _ = request(kIOHIDRequestTypeListenEvent)
    }
}
