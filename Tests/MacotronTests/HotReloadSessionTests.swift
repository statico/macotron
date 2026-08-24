import Foundation
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@MainActor
@Suite("HotReloadSession")
struct HotReloadSessionTests {
    private func makeWorkspace() throws -> (PluginWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-hotreload-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        return (ws, dir)
    }

    private func writeMaliciousHotReloadSettings(_ ws: PluginWorkspace) throws {
        try ws.updateSettings { settings in
            var ui = settings["ui"] as? [String: Any] ?? [:]
            ui["hotReload"] = true
            settings["ui"] = ui
        }
    }

    @Test("ui.hotReload in settings.json cannot bypass plugin trust")
    func settingsHotReloadCannotBypassTrust() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeMaliciousHotReloadSettings(ws)

        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer { PluginTrust.store = previous }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        #expect(!manager.hotReload)

        try "$$__registerCommand('evil-cmd', 'evil', function(){});"
            .write(to: ws.pluginsDir.appending(path: "evil.js"), atomically: true, encoding: .utf8)

        manager.onDidReload = {}
        manager.handleDiskChange([ws.settingsFile.path(percentEncoded: false)])

        #expect(!manager.hotReload)
        manager.reloadAll()
        #expect(manager.pendingReview.contains("evil.js"))
        #expect(engine.commandRegistry["evil.js/evil-cmd"] == nil)
    }

    @Test("session hotReload toggle bypasses trust until relaunch")
    func sessionHotReloadWorks() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "$$__registerCommand('evil-cmd', 'evil', function(){});"
            .write(to: ws.pluginsDir.appending(path: "evil.js"), atomically: true, encoding: .utf8)

        let previous = PluginTrust.store
        PluginTrust.store = MemoryHashStore()
        defer { PluginTrust.store = previous }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.hotReload = true
        manager.reloadAll()

        #expect(manager.pendingReview.isEmpty)
        #expect(engine.commandRegistry["evil.js/evil-cmd"] != nil)
        #expect((ws.readSettings()["ui"] as? [String: Any])?["hotReload"] as? Bool != true)
    }

    @Test("hot reload approves what it runs, so turning it off leaves no queue")
    func hotReloadApprovesWhatItRuns() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "$$__registerCommand('cmd', 'cmd', function(){});"
            .write(to: ws.pluginsDir.appending(path: "edited.js"), atomically: true, encoding: .utf8)

        let previous = PluginTrust.store
        PluginTrust.store = MemoryHashStore()
        defer { PluginTrust.store = previous }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.hotReload = true
        manager.reloadAll()

        manager.hotReload = false
        manager.reloadAll()
        #expect(manager.pendingReview.isEmpty)
        #expect(engine.commandRegistry["edited.js/cmd"] != nil)
    }

    @Test("session toggle must not persist hotReload to settings.json")
    func sessionToggleDoesNotPersist() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        let state = SettingsState()

        manager.hotReload = true
        state.hotReload = true

        let ui = ws.readSettings()["ui"] as? [String: Any]
        #expect(ui?["hotReload"] as? Bool != true)
    }
}
