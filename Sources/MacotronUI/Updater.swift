// Updater.swift — Sparkle self-updates
import AppKit
import Sparkle

/// Sparkle shows a background app's scheduled update window behind everything
/// else, and Macotron has no Dock icon to notice it by. Opting into gentle
/// reminders lets the menu bar carry the notice instead.
@MainActor
final class UpdateReminder: NSObject, SPUStandardUserDriverDelegate {
    /// Version a scheduled check found, until the session ends.
    private(set) var pendingVersion: String?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated { self.pendingVersion = version }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { self.pendingVersion = nil }
    }
}

@MainActor
public enum Updater {
    private static let reminder = UpdateReminder()
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: reminder
    )

    /// Touches the lazy static so the scheduled background check starts.
    public static func start() {
        _ = controller
    }

    /// Sparkle activates the app itself before showing its window.
    public static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Version a scheduled check is waiting to install, for the menu bar.
    public static var pendingVersion: String? {
        reminder.pendingVersion
    }

    /// Sparkle keeps this in the app's UserDefaults itself.
    public static var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
