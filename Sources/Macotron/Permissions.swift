// Permissions.swift — Check and request macOS permissions
@preconcurrency import ApplicationServices
import AppKit
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
        // IOHIDCheckAccess checks Input Monitoring on macOS 15+.
        // Falls back to true if unavailable (pre-Sequoia or sandbox).
        let kIOHIDRequestTypeListenEvent: UInt32 = 1
        typealias IOHIDCheckAccessFunc = @convention(c) (UInt32) -> Bool
        guard let handle = dlopen(nil, RTLD_LAZY),
              let sym = dlsym(handle, "IOHIDCheckAccess") else {
            return true // Assume granted if API unavailable
        }
        let check = unsafeBitCast(sym, to: IOHIDCheckAccessFunc.self)
        return check(kIOHIDRequestTypeListenEvent)
    }

    /// Check if Screen Recording permission is granted
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompt for Accessibility permission if not granted
    public static func requestAccessibility() {
        guard !isAccessibilityGranted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        logger.info("Requested Accessibility permission")
    }

    /// Open System Settings to the appropriate pane
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
