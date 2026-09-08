// Updater.swift — Sparkle self-updates
import AppKit
import MacotronEngine
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

    /// Sparkle activates the app itself before showing its window, but the
    /// status bar menu is still closing on that pass and takes focus back with
    /// it (SettingsWindow has the same problem). Sparkle's window also arrives
    /// later, after the appcast fetch, so keep fronting it for a few seconds.
    public static func checkForUpdates() {
        AppActivation.activate("check for updates")
        controller.checkForUpdates(nil)
        frontSparkleWindows(attempts: 12)
    }

    private static func frontSparkleWindows(attempts: Int) {
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // SUUpdateAlert, SUStatusController, SPUUpdatePermissionPrompt.
            let sparkle = NSApp.windows.filter { window in
                guard window.isVisible, let controller = window.windowController else { return false }
                let name = "\(type(of: controller))"
                return name.hasPrefix("SU") || name.hasPrefix("SPU")
            }
            if sparkle.isEmpty {
                frontSparkleWindows(attempts: attempts - 1)
                return
            }
            AppActivation.activate("update window")
            for window in sparkle where !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
