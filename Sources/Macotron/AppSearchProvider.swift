// AppSearchProvider.swift — Discover and search all installed applications
import AppKit
import MacotronUI
import MacotronEngine
import Modules

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

        for dir in AppCatalog.searchDirectories() {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            contents.forEach(add)
        }
        AppCatalog.extraApps.forEach(add)

        allApps = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastRefresh = Date()
    }

    /// Search apps by query, returns sorted results
    func search(_ query: String) -> [SearchResult] {
        // Refresh every 30 seconds
        if Date().timeIntervalSince(lastRefresh) > 30 {
            refresh()
        }

        guard !query.isEmpty else { return [] }

        var scored: [(entry: AppEntry, score: Int)] = []
        for app in allApps {
            if let s = FuzzyMatch.score(query: query, target: app.name), s > 0 {
                scored.append((app, s))
            }
        }

        scored.sort { $0.score > $1.score }

        return scored.prefix(20).map { item in
            SearchResult(
                id: item.entry.bundleID,
                title: item.entry.name,
                subtitle: "",
                type: .app,
                nsImage: item.entry.icon
            )
        }
    }

    func entry(bundleID: String) -> AppEntry? {
        if Date().timeIntervalSince(lastRefresh) > 30 {
            refresh()
        }
        return allApps.first(where: { $0.bundleID == bundleID })
    }

    /// Launch or switch to an app by bundle ID. A shortcut can hide if it is already front.
    func launchApp(bundleID: String, hideIfFrontmost: Bool = false) {
        AppLaunch.open(bundleID: bundleID, hideIfFrontmost: hideIfFrontmost)
    }

    /// Reveal an app in Finder
    func revealInFinder(bundleID: String) {
        if let app = allApps.first(where: { $0.bundleID == bundleID }) {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
    }
}
