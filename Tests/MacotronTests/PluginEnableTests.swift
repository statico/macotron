// PluginEnableTests.swift — disabledPlugins filtering and persistence
import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Plugin enable/disable")
struct PluginEnableTests {
    private func makeWorkspace() throws -> (PluginWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        return (ws, dir)
    }

    @Test("listModules returns filenames without reading plugin source")
    func listModulesDoesNotReadSource() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "// Huge weather plugin\nconst x = 1;\n"
            .write(to: ws.pluginsDir.appending(path: "demo-weather.js"), atomically: true, encoding: .utf8)

        let manager = ModuleManager(engine: Engine(), workspace: ws)
        let listed = manager.listModules()
        #expect(listed.map(\.filename) == ["demo-weather.js"])
        #expect(listed.map(\.description) == [""])
    }

    @Test("setModuleEnabled persists to settings.json")
    func setModuleEnabledPersists() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModuleManager(engine: Engine(), workspace: ws)

        #expect(!manager.disabledPlugins().contains("a.js"))

        manager.setModuleEnabled(filename: "a.js", enabled: false)
        #expect(manager.disabledPlugins().contains("a.js"))
        #expect(ws.readSettings()["disabledPlugins"] as? [String] == ["a.js"])

        manager.setModuleEnabled(filename: "a.js", enabled: true)
        #expect(!manager.disabledPlugins().contains("a.js"))
        #expect((ws.readSettings()["disabledPlugins"] as? [String])?.isEmpty == true)
    }

    @Test("reloadAll skips disabled plugins")
    func reloadSkipsDisabled() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        // macotron-runtime.js is not in the test bundle, so plugins under test
        // use the core global directly instead of macotron.command().
        try "$$__registerCommand('enabled-cmd', 'on', function(){});"
            .write(to: ws.pluginsDir.appending(path: "a-enabled.js"), atomically: true, encoding: .utf8)
        try "$$__registerCommand('disabled-cmd', 'off', function(){});"
            .write(to: ws.pluginsDir.appending(path: "b-disabled.js"), atomically: true, encoding: .utf8)

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.setModuleEnabled(filename: "b-disabled.js", enabled: false)
        manager.reloadAll()

        #expect(engine.commandRegistry["a-enabled.js/enabled-cmd"] != nil)
        #expect(engine.commandRegistry["b-disabled.js/disabled-cmd"] == nil)
    }

    @Test("disabling the same filename twice is idempotent")
    func disablingIsIdempotent() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModuleManager(engine: Engine(), workspace: ws)

        manager.setModuleEnabled(filename: "dupe.js", enabled: false)
        manager.setModuleEnabled(filename: "dupe.js", enabled: false)
        #expect(ws.readSettings()["disabledPlugins"] as? [String] == ["dupe.js"])
    }

    @Test("deleting a plugin prunes disabledPlugins so reinstall loads enabled")
    func deletePrunesDisabledPlugins() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let pluginFile = ws.pluginsDir.appending(path: "regression.js")
        try "$$__registerCommand('regression-cmd', 'regression', function(){});"
            .write(to: pluginFile, atomically: true, encoding: .utf8)

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)

        manager.setModuleEnabled(filename: "regression.js", enabled: false)
        #expect(manager.disabledPlugins().contains("regression.js"))

        #expect(manager.deleteModule(filename: "regression.js"))
        #expect(!manager.disabledPlugins().contains("regression.js"))
        #expect((ws.readSettings()["disabledPlugins"] as? [String])?.isEmpty == true)

        try "$$__registerCommand('regression-cmd', 'regression', function(){});"
            .write(to: pluginFile, atomically: true, encoding: .utf8)
        manager.reloadAll()

        #expect(engine.commandRegistry["regression.js/regression-cmd"] != nil)
        #expect(!manager.disabledPlugins().contains("regression.js"))
    }
}
