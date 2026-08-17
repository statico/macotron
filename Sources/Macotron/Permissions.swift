// Permissions.swift — Check and request macOS permissions
@preconcurrency import ApplicationServices
import AppKit
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "permissions")

@MainActor
public enum Permissions {
    /// Check if Accessibility permission is granted
    public static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Check if Input Monitoring permission is granted (CGEventTap access)
    public static var isInputMonitoringGranted: Bool {
        // IOHIDCheckAccess returns IOHIDAccessType (granted=0), not Bool.
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDCheckAccessFunc = @convention(c) (UInt32) -> UInt32
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "IOHIDCheckAccess") {
            let check = unsafeBitCast(sym, to: IOHIDCheckAccessFunc.self)
            return HIDAccess.isGranted(check(kIOHIDRequestTypeListenEvent))
        }

        // Fallback for pre-Sequoia: try creating a passive event tap.
        // If this fails, Input Monitoring is not granted.
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

    /// Check if Screen Recording permission is granted
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompt for Accessibility permission — adds the app to the system list and opens a prompt
    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        logger.info("Requested Accessibility permission")
    }

    /// Prompt for Input Monitoring permission, then open the Settings pane.
    /// IOHIDRequestAccess only shows a one-shot dialog; later clicks must open Settings.
    public static func requestInputMonitoring() {
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDRequestAccessFunc = @convention(c) (UInt32) -> Bool
        if let handle = dlopen(nil, RTLD_LAZY),
           let sym = dlsym(handle, "IOHIDRequestAccess") {
            let request = unsafeBitCast(sym, to: IOHIDRequestAccessFunc.self)
            _ = request(kIOHIDRequestTypeListenEvent)
            logger.info("Requested Input Monitoring permission via IOHIDRequestAccess")
        }
        openInputMonitoringSettings()
    }

    /// Prompt for Screen Recording permission — adds the app to the system list
    public static func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        logger.info("Requested Screen Recording permission")
    }

    /// Open System Settings to the appropriate pane
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
