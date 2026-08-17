// PluginWorkspace.swift — User-chosen plugins directory (git workdir for external agents)
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "workspace")

@MainActor
public final class PluginWorkspace {
    public static let directoryDefaultsKey = "pluginsDirectory"

    public let root: URL

    public var pluginsDir: URL { root.appending(path: "plugins") }
    public var cacheDir: URL { root.appending(path: ".cache") }
    public var settingsFile: URL { root.appending(path: "settings.json") }

    public init(root: URL) {
        self.root = root
    }

    // MARK: - Resolve

    /// Resolve the plugins directory from UserDefaults (bookmark Data or path String).
    /// Returns nil if unset or invalid.
    public static func resolveFromDefaults(
        defaults: UserDefaults = .standard
    ) -> URL? {
        let value = defaults.object(forKey: directoryDefaultsKey)
        if let data = value as? Data {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            if isStale {
                savePath(url, defaults: defaults)
            }
            return url
        }
        if let path = value as? String, !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return nil
    }

    /// Persist a directory path (and security-scoped bookmark when possible).
    public static func savePath(_ url: URL, defaults: UserDefaults = .standard) {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: directoryDefaultsKey)
        } else {
            defaults.set(url.path(percentEncoded: false), forKey: directoryDefaultsKey)
        }
    }

    // MARK: - Ensure ready

    /// Create layout, git repo, seed README once, always rewrite AGENTS.md + CLAUDE.md.
    public func ensureReady() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        migrateLegacyModulesIfNeeded()

        let gitignore = root.appending(path: ".gitignore")
        try Self.gitignoreContents.write(to: gitignore, atomically: true, encoding: .utf8)

        let gitDir = root.appending(path: ".git")
        if !fm.fileExists(atPath: gitDir.path(percentEncoded: false)) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["init"]
            proc.currentDirectoryURL = root
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                logger.error("git init failed with status \(proc.terminationStatus)")
            }
        }

        let readme = root.appending(path: "README.md")
        if !fm.fileExists(atPath: readme.path(percentEncoded: false)) {
            try Self.readmeTemplate.write(to: readme, atomically: true, encoding: .utf8)
        }

        try Self.agentsTemplate.write(
            to: root.appending(path: "AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        try Self.claudeTemplate.write(
            to: root.appending(path: "CLAUDE.md"),
            atomically: true,
            encoding: .utf8
        )

        if !fm.fileExists(atPath: settingsFile.path(percentEncoded: false)) {
            try writeSettings(Self.defaultSettings)
        }
    }

    /// One-time move of legacy modules/ into plugins/ when plugins/ is empty.
    private func migrateLegacyModulesIfNeeded() {
        let fm = FileManager.default
        let legacy = root.appending(path: "modules")
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }

        let existing = (try? fm.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: nil
        )) ?? []
        let hasPlugins = existing.contains { $0.pathExtension == "js" }
        guard !hasPlugins else { return }

        guard let files = try? fm.contentsOfDirectory(
            at: legacy, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "js" {
            let dest = pluginsDir.appending(path: file.lastPathComponent)
            try? fm.moveItem(at: file, to: dest)
            logger.info("Migrated \(file.lastPathComponent) to plugins/")
        }
    }

    // MARK: - Settings

    public func readSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Self.defaultSettings
        }
        return json
    }

    public func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsFile, options: .atomic)
    }

    public func updateSettings(_ mutate: (inout [String: Any]) -> Void) throws {
        var settings = readSettings()
        mutate(&settings)
        try writeSettings(settings)
    }

    // MARK: - Defaults & templates

    public static let defaultSettings: [String: Any] = [
        "launcher": ["hotkey": "cmd+space"],
        "ui": ["showDockIcon": true, "showMenuBarIcon": true],
        "modules": [:] as [String: Any],
        "security": ["shell": ["allow": [] as [String], "strict": false]],
    ]

    public static let gitignoreContents = """
    AGENTS.md
    CLAUDE.md
    .cache/
    """

    public static let agentsBanner = "<!-- DO NOT EDIT — Macotron overwrites this file. -->"

    public static var agentsTemplate: String {
        """
        \(agentsBanner)

        # Macotron plugins directory

        This directory is the Macotron workdir. External coding agents edit plugins here.
        Macotron loads the plugins and runs them. The app does not write plugin code.

        ## Layout

        - `plugins/*.js` — plugin scripts. Macotron loads every `.js` file in alphabetical order.
        - `settings.json` — launcher hotkey, UI prefs, module options. Do not put secrets here.
        - `.cache/` — bytecode cache. Gitignored. Do not edit.
        - `AGENTS.md` / `CLAUDE.md` — owned by Macotron. Overwritten on every launch.

        ## Plugins

        Put one `.js` file per plugin under `plugins/`. Register hotkeys at load time:

        ```js
        macotron.keyboard.on("cmd+shift+h", () => {
          macotron.notify.show("Hello", "From a Macotron plugin");
        });
        ```

        ## Permissions

        Declare the macOS permissions a plugin needs at the top of the file:

        ```js
        macotron.requirePermissions(["accessibility"]);
        ```

        Valid names: `accessibility`, `inputMonitoring`, `screenRecording`.
        Macotron shows a red warning in the menu bar until the user grants them.
        Window control needs `accessibility`. Screen capture needs `screenRecording`.

        ## Panel API (stub)

        ```js
        const id = macotron.panel.open({ title: "Chat", width: 420, height: 520, html: "..." });
        macotron.panel.close(id);
        macotron.panel.postMessage(id, { hello: true });
        macotron.panel.onMessage(id, (data) => { /* ... */ });
        ```

        The page may call `webkit.messageHandlers.macotron.postMessage(data)`.

        ## settings.json schema

        ```json
        {
          "launcher": { "hotkey": "cmd+space" },
          "ui": { "showDockIcon": true, "showMenuBarIcon": true },
          "modules": {},
          "security": { "shell": { "allow": [], "strict": false } }
        }
        ```

        ## Git

        Commit often on `main`. Never commit secrets (API keys, tokens, passwords).
        Store secrets with `macotron.keychain`. Macotron only runs `git init`; you commit.

        ## AI from plugins

        Plugins may call `macotron.ai.claude()`, `macotron.ai.openai()`, or `macotron.ai.local()`.
        Read API keys from the keychain: `macotron.keychain.get("anthropic-api-key")`.
        """
    }

    public static var claudeTemplate: String {
        """
        \(agentsBanner)

        See AGENTS.md in this directory. Macotron overwrites both files.
        """
    }

    public static let readmeTemplate = """
    # Macotron plugins

    This folder is your Macotron workdir. Add JavaScript plugins under `plugins/`.

    Open this folder in Cursor or Claude Code to edit plugins. Macotron reloads on save.

    See `AGENTS.md` for API notes (that file is rewritten by the app — do not edit it).
    """
}
