// AppSearchProvider.swift — Discover and search all installed applications
import AppKit
import OSLog
import MacotronUI
import MacotronEngine
import Modules

private let searchLogger = Logger(subsystem: "io.statico.macotron", category: "search")

@MainActor
final class AppSearchProvider {
    /// Built on a background queue and handed to the main actor once. The
    /// icons are only read on main afterwards.
    struct AppEntry: @unchecked Sendable {
        let name: String
        let bundleID: String
        let url: URL
        let icon: NSImage
    }

    private var allApps: [AppEntry] = []
    private var lastRefresh: Date = .distantPast
    private var refreshing = false

    init() {
        refresh()
    }

    /// Rebuild the list in the background. Reading every bundle and its icon
    /// costs ~130ms, which is a visible stall if it lands on a keystroke.
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        lastRefresh = Date()
        Task.detached(priority: .userInitiated) {
            let entries = Self.scan()
            await MainActor.run {
                self.allApps = entries
                self.lastRefresh = Date()
                self.refreshing = false
            }
        }
    }

    nonisolated private static func scan() -> [AppEntry] {
        var seen = Set<String>()
        var entries: [AppEntry] = []

        let fm = FileManager.default
        let workspace = NSWorkspace.shared

        func add(_ url: URL) {
            guard url.pathExtension == "app" else { return }
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier else { return }
            guard !seen.contains(bundleID) else { return }
            seen.insert(bundleID)

            let name = fm.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            entries.append(AppEntry(name: name, bundleID: bundleID, url: url, icon: icon))
        }

        AppCatalog.allBundles().forEach(add)

        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Serves the list it has; a stale one refreshes behind the search.
    private func refreshIfStale() {
        if Date().timeIntervalSince(lastRefresh) > 30 {
            refresh()
        }
    }

    func all() -> [AppEntry] {
        refreshIfStale()
        return allApps
    }

    func matching(_ query: String, limit: Int = 12) -> [AppEntry] {
        let apps = all()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(apps.prefix(limit)) }
        var scored: [(entry: AppEntry, score: Int)] = []
        for app in apps {
            if let s = FuzzyMatch.score(query: q, target: app.name), s > 0 {
                scored.append((app, s))
            }
        }
        scored.sort { $0.score > $1.score }
        return scored.prefix(limit).map(\.entry)
    }

    func entry(bundleID: String) -> AppEntry? {
        refreshIfStale()
        return allApps.first(where: { $0.bundleID == bundleID })
    }

    /// Launch or switch to an app by bundle ID. A shortcut can hide if it is already front.
    func launchApp(bundleID: String, hideIfFrontmost: Bool = false) {
        AppLaunch.open(bundleID: bundleID, hideIfFrontmost: hideIfFrontmost)
    }

    /// Reveal an app in Finder
    func revealInFinder(bundleID: String) {
        guard let app = allApps.first(where: { $0.bundleID == bundleID }) else {
            searchLogger.notice("reveal: no app for \(bundleID, privacy: .public)")
            return
        }
        searchLogger.notice("reveal: \(app.url.path, privacy: .public)")
        NSWorkspace.shared.revealInFinder(app.url)
    }
}

extension NSWorkspace {
    /// Select a file in Finder and bring Finder forward.
    ///
    /// `activateFileViewerSelecting` is a one-way request with no result, and
    /// on this machine it selects nothing and Finder never appears, both on
    /// its own and after yielding activation. So check afterwards whether
    /// Finder actually came forward, and fall back to `open -R`, which asks
    /// LaunchServices from outside this process.
    @MainActor
    func revealInFinder(_ url: URL) {
        let finder = "com.apple.finder"
        searchLogger.notice(
            """
            reveal before: front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public)             active=\(NSApp.isActive)             finderRunning=\(!NSRunningApplication.runningApplications(withBundleIdentifier: finder).isEmpty)
            """
        )
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: finder)
        activateFileViewerSelecting([url])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
            searchLogger.notice("reveal after: front=\(front, privacy: .public)")
            guard front != finder else { return }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-R", url.path]
            do {
                try open.run()
                searchLogger.notice("reveal fallback: open -R ran")
            } catch {
                searchLogger.error("reveal fallback failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
