// Permissions.swift — Check, request, and explain macOS privacy permissions
@preconcurrency import ApplicationServices
import AppKit
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "permissions")

public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case inputMonitoring
    case accessibility
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    /// Short reason shown in Settings so the user knows why Macotron asks.
    public var reason: String {
        switch self {
        case .inputMonitoring: return "Global hotkeys for the launcher and plugins."
        case .accessibility: return "Move and focus windows from plugins."
        case .screenRecording: return "Capture the screen for plugins that read it."
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
        }
    }

    /// Ask macOS for the permission. This also registers Macotron in the
    /// matching System Settings list, so the user can find the toggle.
    @MainActor
    public func request() {
        switch self {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            Permissions.requestInputMonitoring()
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        }
        logger.info("Requested \(self.rawValue) permission")
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
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
public enum Permissions {
    /// Always required, whether or not any plugin is installed.
    public static let baseline: [Permission] = [.inputMonitoring, .accessibility]

    /// Map a plugin declaration string to a permission.
    public static func parse(_ name: String) -> Permission? {
        switch name.lowercased() {
        case "inputmonitoring", "input-monitoring", "keyboard", "hotkeys":
            return .inputMonitoring
        case "accessibility", "window", "windows":
            return .accessibility
        case "screenrecording", "screen-recording", "screen", "screencapture":
            return .screenRecording
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
    /// app in the System Settings list.
    public static func registerWithSystem(_ required: [Permission]) {
        for permission in missing(from: required) {
            permission.request()
        }
    }

    // MARK: - Input Monitoring internals

    static var isInputMonitoringGranted: Bool {
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDCheckAccessFunc = @convention(c) (UInt32) -> UInt32
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "IOHIDCheckAccess") {
            let check = unsafeBitCast(sym, to: IOHIDCheckAccessFunc.self)
            return HIDAccess.isGranted(check(kIOHIDRequestTypeListenEvent))
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
