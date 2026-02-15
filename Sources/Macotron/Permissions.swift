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
