// PluginWorkspace.swift — User-chosen plugins directory (git workdir for external agents)
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "workspace")

@MainActor
public final class PluginWorkspace {
    public static let directoryDefaultsKey = "pluginsDirectory"

    public let root: URL

    public var pluginsDir: URL { root.appending(path: "plugins") }
    public var cacheDir: URL { root.appending(path: ".cache") }
    public var settingsFile: URL { root.appending(path: "settings.json") }

    /// Parsed settings.json, keyed by the file's modification date and size so
    /// an external edit still wins. Search reads settings on every keystroke.
    private var settingsCache: (stamp: [AnyHashable: Any], value: [String: Any])?

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

        try seedTypecheckCache()
        migrateLegacyModulesIfNeeded()

        let gitignore = root.appending(path: ".gitignore")
        try Self.gitignoreContents.write(to: gitignore, atomically: true, encoding: .utf8)

        let gitDir = root.appending(path: ".git")
        if !fm.fileExists(atPath: gitDir.path(percentEncoded: false)), Self.gitIsUsable() {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["init"]
            proc.currentDirectoryURL = root
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    logger.error("git init failed with status \(proc.terminationStatus)")
                }
            } catch {
                logger.error("git init skipped: \(error.localizedDescription)")
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
        migratePluginNames(PluginCatalog.legacyRenames)
    }

    public func migratePluginNames(
        _ renames: [String: String],
        hashStore: PluginHashStore = PluginTrust.store
    ) {
        let fm = FileManager.default
        var settings = readSettings()

        for (oldName, newName) in renames.sorted(by: { $0.key < $1.key }) {
            let src = pluginsDir.appending(path: oldName)
            let dest = pluginsDir.appending(path: newName)
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
            guard !fm.fileExists(atPath: dest.path(percentEncoded: false)) else { continue }
            if let conflict = stateConflict(
                in: settings,
                oldName: oldName,
                newName: newName,
                hashStore: hashStore
            ) {
                logger.error(
                    "Kept \(oldName) because \(newName) already has \(conflict) state"
                )
                continue
            }
            do {
                try fm.moveItem(at: src, to: dest)
            } catch {
                logger.error("Failed to migrate \(oldName) to \(newName): \(error.localizedDescription)")
                continue
            }

            let settingsBefore = settings
            let changedSettings = applySettingsMigration(&settings, oldName: oldName, newName: newName)

            if changedSettings {
                do {
                    try writeSettings(settings)
                } catch {
                    logger.error(
                        "Failed to save settings after migrating \(oldName): \(error.localizedDescription)"
                    )
                    settings = settingsBefore
                    do {
                        try fm.moveItem(at: dest, to: src)
                    } catch {
                        logger.error(
                            "Failed to roll back \(newName) to \(oldName): \(error.localizedDescription)"
                        )
                    }
                    continue
                }
            }

            PluginTrust.migrateHash(from: oldName, to: newName, store: hashStore)
        }
    }

    /// The stored id a plugin-scoped id becomes after the rename, or nil when the id
    /// belongs to another plugin.
    private static func migratedID(_ id: String, oldName: String, newName: String) -> String? {
        if id == oldName { return newName }
        if id.hasPrefix(oldName + "/") { return newName + String(id.dropFirst(oldName.count)) }
        return nil
    }

    /// Name of the first state category that already holds the destination identity.
    /// Migrating would then have to pick a winner, so the caller keeps the old file.
    private func stateConflict(
        in settings: [String: Any],
        oldName: String,
        newName: String,
        hashStore: PluginHashStore
    ) -> String? {
        if let table = settings["pluginSettings"] as? [String: [String: Any]],
           table[oldName] != nil, table[newName] != nil {
            return "plugin settings"
        }
        if let disabled = settings["disabledPlugins"] as? [String],
           disabled.contains(oldName), disabled.contains(newName) {
            return "disabled plugin"
        }
        for key in ["commandShortcuts", "keyboardShortcuts"] {
            guard let table = settings[key] as? [String: String] else { continue }
            let collides = table.keys.contains { id in
                guard let migrated = Self.migratedID(id, oldName: oldName, newName: newName) else {
                    return false
                }
                return table[migrated] != nil
            }
            if collides { return key }
        }
        if let favorites = settings["launcherFavorites"] as? [String] {
            let ids = Set(favorites)
            let collides = favorites.contains { id in
                guard let migrated = Self.migratedID(id, oldName: oldName, newName: newName) else {
                    return false
                }
                return ids.contains(migrated)
            }
            if collides { return "launcher favorite" }
        }
        if hashStore.read(filename: oldName) != nil, hashStore.read(filename: newName) != nil {
            return "approved hash"
        }
        return nil
    }

    private func applySettingsMigration(
        _ settings: inout [String: Any],
        oldName: String,
        newName: String
    ) -> Bool {
        var changed = false
        changed = migratePluginSettings(&settings, oldName: oldName, newName: newName) || changed
        changed = migrateDisabledPlugins(&settings, oldName: oldName, newName: newName) || changed
        changed = migrateShortcutTable(&settings, key: "commandShortcuts", oldName: oldName, newName: newName)
            || changed
        changed = migrateShortcutTable(&settings, key: "keyboardShortcuts", oldName: oldName, newName: newName)
            || changed
        changed = migrateFavoriteIDs(&settings, oldName: oldName, newName: newName) || changed
        return changed
    }

    private func migratePluginSettings(
        _ settings: inout [String: Any],
        oldName: String,
        newName: String
    ) -> Bool {
        guard var table = settings["pluginSettings"] as? [String: [String: Any]],
              let value = table.removeValue(forKey: oldName) else {
            return false
        }
        table[newName] = value
        settings["pluginSettings"] = table
        return true
    }

    private func migrateDisabledPlugins(
        _ settings: inout [String: Any],
        oldName: String,
        newName: String
    ) -> Bool {
        guard var disabled = settings["disabledPlugins"] as? [String] else { return false }
        guard disabled.contains(oldName) else { return false }
        disabled = disabled.map { $0 == oldName ? newName : $0 }
        settings["disabledPlugins"] = disabled
        return true
    }

    private func migrateShortcutTable(
        _ settings: inout [String: Any],
        key: String,
        oldName: String,
        newName: String
    ) -> Bool {
        guard var table = settings[key] as? [String: String] else { return false }
        let affected = table.keys
            .filter { Self.migratedID($0, oldName: oldName, newName: newName) != nil }
            .sorted()
        guard !affected.isEmpty else { return false }
        for id in affected {
            guard let migrated = Self.migratedID(id, oldName: oldName, newName: newName),
                  let combo = table.removeValue(forKey: id) else { continue }
            table[migrated] = combo
        }
        settings[key] = table
        return true
    }

    private func migrateFavoriteIDs(
        _ settings: inout [String: Any],
        oldName: String,
        newName: String
    ) -> Bool {
        guard let favorites = settings["launcherFavorites"] as? [String] else { return false }
        let migrated = favorites.map {
            Self.migratedID($0, oldName: oldName, newName: newName) ?? $0
        }
        guard migrated != favorites else { return false }
        settings["launcherFavorites"] = migrated
        return true
    }

    /// Real git, not the Xcode CLT stub. Workdir still works without it.
    private static func gitIsUsable() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        proc.arguments = ["-p"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Copy bundle `macotron.d.ts` and seed `.cache/jsconfig.json` for agent typecheck.
    private func seedTypecheckCache() throws {
        let dtsDest = cacheDir.appending(path: "macotron.d.ts")
        if let src = Bundle.main.url(forResource: "macotron", withExtension: "d.ts") {
            try? FileManager.default.removeItem(at: dtsDest)
            do {
                try FileManager.default.copyItem(at: src, to: dtsDest)
            } catch {
                logger.error("Failed to copy macotron.d.ts: \(error.localizedDescription)")
            }
        } else {
            logger.info("macotron.d.ts not in bundle; skipping copy")
        }

        let jsconfig = """
        {
          "compilerOptions": {
            "checkJs": true,
            "noEmit": true,
            "strict": true,
            "target": "ES2020",
            "module": "ESNext",
            "types": []
          },
          "files": ["macotron.d.ts"],
          "include": ["../plugins/**/*.js"]
        }
        """
        try jsconfig.write(
            to: cacheDir.appending(path: "jsconfig.json"),
            atomically: true,
            encoding: .utf8
        )
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
        let stamp = (try? FileManager.default.attributesOfItem(
            atPath: settingsFile.path(percentEncoded: false)
        )) ?? [:]
        if let cached = settingsCache,
           cached.stamp[FileAttributeKey.modificationDate] as? Date
               == stamp[FileAttributeKey.modificationDate] as? Date,
           cached.stamp[FileAttributeKey.size] as? Int == stamp[FileAttributeKey.size] as? Int {
            return cached.value
        }
        let value = StepTimer.measure("readSettings") { readSettingsUncached() }
        settingsCache = (stamp, value)
        return value
    }

    private func readSettingsUncached() -> [String: Any] {
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
        settingsCache = nil
    }

    public func updateSettings(_ mutate: (inout [String: Any]) -> Void) throws {
        var settings = readSettings()
        mutate(&settings)
        try writeSettings(settings)
    }

    // MARK: - Defaults & templates

    public static let defaultSettings: [String: Any] = [
        "launcher": ["hotkey": "opt+space"],
        "ui": [
            "showMenuBarIcon": true,
            "appearance": "system",
            "textScale": 1.0,
            "launcherBackground": "translucent",
            "hotReload": false,
        ],
        "modules": [:] as [String: Any],
        "pluginSettings": [:] as [String: Any],
        "disabledPlugins": [] as [String],
        "commandShortcuts": [:] as [String: String],
        "keyboardShortcuts": [:] as [String: String],
        "launcherFavorites": [] as [String],
    ]

    public static let gitignoreContents = """
    AGENTS.md
    CLAUDE.md
    .cache/
    """

    public static let agentsBanner = "<!-- DO NOT EDIT — Macotron overwrites this file. -->"

    /// The AGENTS.md body lives in `Resources/agents-template.md` so it can be
    /// edited as markdown. Trailing newlines are trimmed, and `{{API_VERSION}}`
    /// is substituted, so the written file is byte-identical to the old literal.
    public static var agentsTemplate: String {
        // Bundle.module points at Bundle.main.bundleURL, which is the .app itself,
        // so `make bundle` puts the file in Contents/Resources like the other
        // resources and Bundle.main finds it. Bundle.module is the test/CLI path.
        let url = Bundle.main.url(forResource: "agents-template", withExtension: "md")
            ?? Bundle.module.url(forResource: "agents-template", withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("agents-template.md missing from bundle")
            return agentsBanner
        }
        return text
            .trimmingCharacters(in: .newlines)
            .replacingOccurrences(of: "{{API_VERSION}}", with: Engine.apiVersion)
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

    Open this folder in Claude Code, Codex, Cursor, or pi.dev to edit plugins. Macotron reloads on save.

    Example plugins live at
    https://github.com/statico/macotron/tree/main/Examples/plugins
    and ship inside the app at
    `/Applications/Macotron.app/Contents/Resources/Catalog/`
    (or `~/Applications/Macotron.app/…` after `make bundle`).

    See `AGENTS.md` for API notes (that file is rewritten by the app — do not edit it).
    """
}
