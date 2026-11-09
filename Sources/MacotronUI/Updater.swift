// Updater.swift — Sparkle self-updates
import AppKit
import MacotronEngine
import SMCKit
import OSLog
import Sparkle

private let logger = Logger(subsystem: "io.statico.macotron", category: "updater")

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

/// A fresh query string on every check, so no CDN or proxy between here and
/// Vercel can answer with an older feed. Sparkle already skips the local cache.
final class UpdateFeed: NSObject, SPUUpdaterDelegate {
    /// Once Homebrew or a drag-install replaces the bundle, this process no
    /// longer matches its signature, and Sparkle's installer rejects it
    /// (-67030) with only "Update Error". Skip checks until a relaunch.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard MacotronHelperService.appReplacedOnDisk else { return }
        throw NSError(domain: "Macotron", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Macotron was replaced on disk since it started. Relaunch it.",
        ])
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] {
        [["key": "t", "value": String(Int(Date().timeIntervalSince1970))]]
    }
}

/// The user already said yes in the update alert, which shows the release
/// notes. Sparkle then asks again with an "Install and Relaunch" window once
/// the download finishes, so answer that one for them.
final class OneConfirmationUserDriver: SPUStandardUserDriver {
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
}

@MainActor
public enum Updater {
    private static let reminder = UpdateReminder()
    private static let feed = UpdateFeed()
    private static let updater: SPUUpdater = {
        let driver = OneConfirmationUserDriver(hostBundle: .main, delegate: reminder)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: feed)
        do {
            try updater.start()
        } catch {
            logger.error("updater failed to start: \(error.localizedDescription, privacy: .public)")
            startError = error
        }
        return updater
    }()
    /// Why Sparkle would not start, shown when the user asks for a check.
    private static var startError: Error?

    /// Touches the lazy static so the scheduled background check starts.
    public static func start() {
        _ = updater
    }

    /// Sparkle activates the app itself before showing its window, but the
    /// status bar menu is still closing on that pass and takes focus back with
    /// it (SettingsWindow has the same problem). Sparkle's window also arrives
    /// later, after the appcast fetch, so keep fronting it for a few seconds.
    public static func checkForUpdates() {
        AppActivation.activate("check for updates")
        if replacedOnDisk {
            offerRelaunch()
            return
        }
        _ = updater
        if let startError {
            let alert = NSAlert()
            alert.messageText = "Unable to Check for Updates"
            alert.informativeText = startError.localizedDescription
            alert.runModal()
            return
        }
        updater.checkForUpdates()
        frontSparkleWindows(attempts: 12)
    }

    /// The bundle on disk is not the code running, so updating waits for a
    /// relaunch. The menu and Settings offer one instead of a check.
    public static var replacedOnDisk: Bool {
        MacotronHelperService.appReplacedOnDisk
    }

    private static func offerRelaunch() {
        let key = "CFBundleShortVersionString"
        // infoDictionary is cached at launch, so read the plist on disk.
        let installed = NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist"))?[key] as? String
        let running = Bundle.main.infoDictionary?[key] as? String
        let alert = NSAlert()
        alert.messageText = "Relaunch Macotron"
        alert.informativeText = installed != nil && installed != running
            ? "Macotron \(installed!) was installed while \(running ?? "an older version") kept running. Relaunch to use it."
            : "Macotron was replaced on disk since it started. Relaunch to use the new copy."
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Wait for this process to exit, or open would just activate it.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while /bin/kill -0 $1 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                              Bundle.main.bundlePath, String(getpid())]
        guard (try? relaunch.run()) != nil else { return }
        NSApp.terminate(nil)
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

    /// Sparkle keeps both settings in the app's UserDefaults itself.
    public static var frequency: UpdateFrequency {
        get {
            guard updater.automaticallyChecksForUpdates else { return .never }
            return updater.updateCheckInterval >= UpdateFrequency.weekly.interval ? .weekly : .daily
        }
        set {
            updater.automaticallyChecksForUpdates = newValue != .never
            if newValue != .never { updater.updateCheckInterval = newValue.interval }
        }
    }
}

public enum UpdateFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case never

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .never: return "Never"
        }
    }

    var interval: TimeInterval {
        self == .weekly ? 7 * 86400 : 86400
    }
}
