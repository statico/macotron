// AppSearchProvider.swift — Discover and search all installed applications
import AppKit
import OSLog
import MacotronUI
import MacotronEngine
import Modules

private let searchLogger = Logger(subsystem: "io.statico.macotron", category: "search")

@MainActor
final class AppSearchProvider {
    struct AppEntry {
        let name: String
        let bundleID: String
        let url: URL
        let icon: NSImage
    }

    private var allApps: [AppEntry] = []
    private var lastRefresh: Date = .distantPast

    init() {
        refresh()
    }

    /// Refresh the list of installed applications
    func refresh() {
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

        allApps = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastRefresh = Date()
    }

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
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }
}
