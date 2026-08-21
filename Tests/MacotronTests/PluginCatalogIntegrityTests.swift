import Foundation
import Darwin
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@Suite("PluginHash")
struct PluginHashTests {
    @Test func sha256IsStable() {
        #expect(PluginHash.sha256(source: "hello") == PluginHash.sha256(source: "hello"))
        #expect(PluginHash.sha256(source: "hello") != PluginHash.sha256(source: "Hello"))
        #expect(PluginHash.sha256(source: "hello").count == 64)
    }
}

@Suite("PluginTrust")
@MainActor
struct PluginTrustTests {
    @Test func matchesApprovedHash() {
        let store = MemoryHashStore()
        PluginTrust.store = store
        defer { PluginTrust.store = KeychainHashStore() }
        PluginTrust.approve(filename: "demo.js", source: "ok")
        #expect(PluginTrust.matches(filename: "demo.js", source: "ok"))
        #expect(!PluginTrust.matches(filename: "demo.js", source: "changed"))
    }

    @Test func grandfathersEmptyLedger() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-trust-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "a".write(to: dir.appending(path: "a.js"), atomically: true, encoding: .utf8)

        let store = MemoryHashStore()
        PluginTrust.grandfatherIfEmpty(pluginsDir: dir, store: store)
        #expect(store.read(filename: "a.js") == PluginHash.sha256(source: "a"))
        store.write(filename: "a.js", hash: "old")
        PluginTrust.grandfatherIfEmpty(pluginsDir: dir, store: store)
        #expect(store.read(filename: "a.js") == "old")
    }
}

@Suite("PluginScan")
struct PluginScanTests {
    @Test func chunksOverlap() {
        let chunks = PluginScan.chunks(String(repeating: "a", count: 50), maxChars: 20, overlap: 5)
        #expect(chunks.count > 1)
        #expect(chunks[0].text.count == 20)
        #expect(chunks[1].text.hasPrefix(String(chunks[0].text.suffix(5))))
    }

    @Test func flagsEval() {
        #expect(PluginScan.staticFlags("eval(code)").contains("Uses eval()"))
        #expect(PluginScan.staticFlags("const x = 1").isEmpty)
    }

    @Test func anyPassFailureFailsReport() {
        let report = PluginScan.failed(
            anyPassFails: [
                [],
                [PluginScanFinding(pass: 2, message: "exfil")],
            ],
            staticFlags: []
        )
        #expect(!report.approved)
        #expect(report.needsOverride)
        #expect(report.findings.map(\.pass) == [2])
    }

    @Test func unavailableModelNeedsOverride() {
        let report = PluginScan.unavailableReport(reason: "Turn on Apple Intelligence in System Settings to get automated checks.")
        #expect(!report.modelAvailable)
        #expect(!report.approved)
        #expect(report.needsOverride)
        #expect(report.unavailableReason?.contains("Apple Intelligence") == true)
    }

    @Test func tokenChunksHonorBudget() {
        let chunks = PluginScan.chunks(
            String(repeating: "a", count: 50),
            maxTokens: 20,
            overlapTokens: 5,
            tokenCount: { $0.count }
        )
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= 20 })
    }
}

@Suite("PluginCatalog")
struct PluginCatalogTests {
    @Test func overwriteKinds() {
        #expect(PluginCatalog.overwriteKind(existingHash: nil, bundledHash: "a") == nil)
        #expect(PluginCatalog.overwriteKind(existingHash: "a", bundledHash: "a") == .unmodifiedStock)
        #expect(PluginCatalog.overwriteKind(existingHash: "b", bundledHash: "a") == .modified)
    }

    @Test func legacyRenamesStripsDemoPrefix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-renames-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appending(path: "demo-weather.js"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appending(path: "demo-night-vision.js"), atomically: true, encoding: .utf8)
        let json = dir.appending(path: "catalog.json")
        try """
        {"plugins":[
          {"filename":"demo-weather.js","kind":"stock","highlighted":true,"category":"Menu bar"},
          {"filename":"demo-night-vision.js","kind":"demo","highlighted":false,"category":"System"}
        ]}
        """.write(to: json, atomically: true, encoding: .utf8)
        let renames = PluginCatalog.legacyRenames(jsonURL: json)
        #expect(renames["demo-weather.js"] == "weather.js")
        #expect(renames["demo-night-vision.js"] == nil)
    }

    @Test func loadsFromJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-cat-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        macotron.plugin({ title: "Weather", description: "Sky", permissions: ["accessibility"] });
        """.write(to: dir.appending(path: "demo-weather.js"), atomically: true, encoding: .utf8)
        let json = dir.appending(path: "catalog.json")
        try """
        {"plugins":[{"filename":"demo-weather.js","kind":"stock","highlighted":true,"category":"Menu bar"}]}
        """.write(to: json, atomically: true, encoding: .utf8)
        let plugins = PluginCatalog.load(jsonURL: json)
        #expect(plugins.count == 1)
        #expect(plugins[0].title == "Weather")
        #expect(plugins[0].highlighted)
        #expect(plugins[0].isStock)
        #expect(plugins[0].permissions == [.accessibility])
        #expect(plugins[0].fileURL.lastPathComponent == "demo-weather.js")
    }

    @MainActor
    private func makeMigrationWorkspace() throws -> (PluginWorkspace, MemoryHashStore) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "macotron-migrate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let workspace = PluginWorkspace(root: root)
        try workspace.ensureReady()
        return (workspace, MemoryHashStore())
    }

    @MainActor
    @Test func migrationMovesPluginFile() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let old = workspace.pluginsDir.appending(path: "demo-weather.js")
        try "weather".write(to: old, atomically: true, encoding: .utf8)
        let renames = ["demo-weather.js": "weather.js"]
        workspace.migratePluginNames(renames, hashStore: hashes)
        #expect(FileManager.default.fileExists(atPath: workspace.pluginsDir.appending(path: "weather.js").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @MainActor
    @Test func migrationSkipsWhenDestinationExists() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let old = workspace.pluginsDir.appending(path: "demo-weather.js")
        let new = workspace.pluginsDir.appending(path: "weather.js")
        try "old".write(to: old, atomically: true, encoding: .utf8)
        try "existing".write(to: new, atomically: true, encoding: .utf8)
        try workspace.writeSettings([
            "pluginSettings": ["demo-weather.js": ["city": "SF"]],
            "disabledPlugins": ["demo-weather.js"],
            "commandShortcuts": ["demo-weather.js/Refresh": "cmd+r"],
            "keyboardShortcuts": ["demo-weather.js/Hotkey": "cmd+w"],
            "launcherFavorites": ["demo-weather.js/Refresh"],
        ])
        hashes.write(filename: "demo-weather.js", hash: "abc123")
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        #expect(try String(contentsOf: new, encoding: .utf8) == "existing")
        #expect(FileManager.default.fileExists(atPath: old.path))
        let settings = workspace.readSettings()
        let pluginSettings = settings["pluginSettings"] as? [String: [String: Any]]
        #expect(pluginSettings?["demo-weather.js"]?["city"] as? String == "SF")
        #expect(settings["disabledPlugins"] as? [String] == ["demo-weather.js"])
        #expect(settings["commandShortcuts"] as? [String: String] == ["demo-weather.js/Refresh": "cmd+r"])
        #expect(settings["keyboardShortcuts"] as? [String: String] == ["demo-weather.js/Hotkey": "cmd+w"])
        #expect(settings["launcherFavorites"] as? [String] == ["demo-weather.js/Refresh"])
        #expect(hashes.read(filename: "demo-weather.js") == "abc123")
        #expect(hashes.read(filename: "weather.js") == nil)
    }

    @MainActor
    @Test func migrationPreservesUnrelatedShortcuts() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": [:] as [String: Any],
            "disabledPlugins": [] as [String],
            "commandShortcuts": [
                "demo-weather.js/Refresh": "cmd+r",
                "demo-notes.js/Open": "cmd+n",
            ],
            "keyboardShortcuts": [
                "demo-weather.js/Hotkey": "cmd+w",
                "demo-notes.js/Toggle": "cmd+t",
            ],
            "launcherFavorites": [] as [String],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let settings = workspace.readSettings()
        let command = settings["commandShortcuts"] as? [String: String]
        let keyboard = settings["keyboardShortcuts"] as? [String: String]
        #expect(command?["weather.js/Refresh"] == "cmd+r")
        #expect(command?["demo-notes.js/Open"] == "cmd+n")
        #expect(keyboard?["weather.js/Hotkey"] == "cmd+w")
        #expect(keyboard?["demo-notes.js/Toggle"] == "cmd+t")
    }

    @MainActor
    @Test func migrationRollsBackFileWhenSettingsWriteFails() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let old = workspace.pluginsDir.appending(path: "demo-weather.js")
        try "weather".write(to: old, atomically: true, encoding: .utf8)
        try workspace.writeSettings([
            "pluginSettings": ["demo-weather.js": ["city": "SF"]],
            "disabledPlugins": [] as [String],
            "commandShortcuts": [:] as [String: String],
            "keyboardShortcuts": [:] as [String: String],
            "launcherFavorites": [] as [String],
        ])
        hashes.write(filename: "demo-weather.js", hash: "abc123")
        let settingsPath = workspace.settingsFile.path(percentEncoded: false)
        try settingsPath.withCString { pointer in
            if chflags(pointer, UInt32(UF_IMMUTABLE)) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
        defer { settingsPath.withCString { _ = chflags($0, 0) } }
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(!FileManager.default.fileExists(atPath: workspace.pluginsDir.appending(path: "weather.js").path))
        let settings = workspace.readSettings()
        let pluginSettings = settings["pluginSettings"] as? [String: [String: Any]]
        #expect(pluginSettings?["demo-weather.js"]?["city"] as? String == "SF")
        #expect(hashes.read(filename: "demo-weather.js") == "abc123")
        #expect(hashes.read(filename: "weather.js") == nil)
    }

    @MainActor
    @Test func migrationRewritesPluginSettingsKey() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": ["demo-weather.js": ["city": "SF"]],
            "disabledPlugins": [] as [String],
            "commandShortcuts": [:] as [String: String],
            "keyboardShortcuts": [:] as [String: String],
            "launcherFavorites": [] as [String],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let settings = workspace.readSettings()
        let pluginSettings = settings["pluginSettings"] as? [String: [String: Any]]
        #expect(pluginSettings?["weather.js"]?["city"] as? String == "SF")
        #expect(pluginSettings?["demo-weather.js"] == nil)
    }

    @MainActor
    @Test func migrationRewritesDisabledPluginName() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": [:] as [String: Any],
            "disabledPlugins": ["demo-weather.js"],
            "commandShortcuts": [:] as [String: String],
            "keyboardShortcuts": [:] as [String: String],
            "launcherFavorites": [] as [String],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let disabled = workspace.readSettings()["disabledPlugins"] as? [String]
        #expect(disabled == ["weather.js"])
    }

    @MainActor
    @Test func migrationRewritesCommandShortcutIDs() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": [:] as [String: Any],
            "disabledPlugins": [] as [String],
            "commandShortcuts": ["demo-weather.js/Refresh": "cmd+r"],
            "keyboardShortcuts": [:] as [String: String],
            "launcherFavorites": [] as [String],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let shortcuts = workspace.readSettings()["commandShortcuts"] as? [String: String]
        #expect(shortcuts?["weather.js/Refresh"] == "cmd+r")
        #expect(shortcuts?["demo-weather.js/Refresh"] == nil)
    }

    @MainActor
    @Test func migrationRewritesKeyboardShortcutIDs() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": [:] as [String: Any],
            "disabledPlugins": [] as [String],
            "commandShortcuts": [:] as [String: String],
            "keyboardShortcuts": ["demo-weather.js/Hotkey": "cmd+shift+w"],
            "launcherFavorites": [] as [String],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let shortcuts = workspace.readSettings()["keyboardShortcuts"] as? [String: String]
        #expect(shortcuts?["weather.js/Hotkey"] == "cmd+shift+w")
        #expect(shortcuts?["demo-weather.js/Hotkey"] == nil)
    }

    @MainActor
    @Test func migrationRewritesLauncherFavoriteIDs() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        try workspace.writeSettings([
            "pluginSettings": [:] as [String: Any],
            "disabledPlugins": [] as [String],
            "commandShortcuts": [:] as [String: String],
            "keyboardShortcuts": [:] as [String: String],
            "launcherFavorites": ["demo-weather.js/Refresh"],
        ])
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        let favorites = workspace.readSettings()["launcherFavorites"] as? [String]
        #expect(favorites == ["weather.js/Refresh"])
    }

    @MainActor
    @Test func migrationMigratesApprovedHash() throws {
        let (workspace, hashes) = try makeMigrationWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        try "x".write(
            to: workspace.pluginsDir.appending(path: "demo-weather.js"),
            atomically: true,
            encoding: .utf8
        )
        hashes.write(filename: "demo-weather.js", hash: "abc123")
        workspace.migratePluginNames(["demo-weather.js": "weather.js"], hashStore: hashes)
        #expect(hashes.read(filename: "weather.js") == "abc123")
        #expect(hashes.read(filename: "demo-weather.js") == nil)
    }
}

@Suite("WizardStep")
struct WizardStepTests {
    @Test func catalogIsBeforePermissions() {
        let steps = WizardStep.allCases
        let catalog = steps.firstIndex(of: .catalog)!
        let folder = steps.firstIndex(of: .folder)!
        let permissions = steps.firstIndex(of: .permissions)!
        #expect(folder < catalog)
        #expect(catalog < permissions)
    }
}
