// AppSearchProvider.swift — Discover and search all installed applications
import AppKit
import MacotronUI
import MacotronEngine

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

        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
        ]

        let fm = FileManager.default
        let workspace = NSWorkspace.shared

        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }
                guard !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = fm.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                entries.append(AppEntry(
                    name: name,
                    bundleID: bundleID,
                    url: url,
                    icon: icon
                ))
            }
        }

        // Also add user-installed apps from ~/Applications
        let home = fm.homeDirectoryForCurrentUser
        let userAppsDir = home.appending(path: "Applications")
        if let contents = try? fm.contentsOfDirectory(
            at: userAppsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in contents {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }
                guard !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = fm.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                entries.append(AppEntry(
                    name: name,
                    bundleID: bundleID,
                    url: url,
                    icon: icon
                ))
            }
        }

        allApps = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lastRefresh = Date()
    }

    /// Search apps by query, returns sorted results
    func search(_ query: String) -> [SearchResult] {
        // Refresh every 30 seconds
        if Date().timeIntervalSince(lastRefresh) > 30 {
            refresh()
        }

        guard !query.isEmpty else {
            // Return top apps when no query (recently used would be ideal, but for now return alphabetical)
            return Array(allApps.prefix(8)).map { app in
                SearchResult(
                    id: app.bundleID,
                    title: app.name,
                    subtitle: app.bundleID,
                    icon: "app.fill",
                    type: .app,
                    nsImage: app.icon,
                    appURL: app.url
                )
            }
        }

        var scored: [(entry: AppEntry, score: Int)] = []
        for app in allApps {
            if let s = FuzzyMatch.score(query: query, target: app.name), s > 0 {
                scored.append((app, s))
            }
        }

        scored.sort { $0.score > $1.score }

        return scored.prefix(20).map { item in
            let isRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: item.entry.bundleID
            ).first != nil

            return SearchResult(
                id: item.entry.bundleID,
                title: item.entry.name,
                subtitle: isRunning ? "Running" : item.entry.bundleID,
                icon: "app.fill",
                type: .app,
                nsImage: item.entry.icon,
                appURL: item.entry.url
            )
        }
    }

    /// Launch or switch to an app by bundle ID
    func launchApp(bundleID: String) {
        // Try to switch to running app first
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            app.activate()
            return
        }

        // Launch the app
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Reveal an app in Finder
    func revealInFinder(bundleID: String) {
        if let app = allApps.first(where: { $0.bundleID == bundleID }) {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
        }
    }
}
