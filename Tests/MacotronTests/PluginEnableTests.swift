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

    @Test("setModuleEnabled persists to settings.json")
    func setModuleEnabledPersists() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = ModuleManager(engine: Engine(), workspace: ws)

        #expect(manager.isModuleEnabled(filename: "a.js"))

        manager.setModuleEnabled(filename: "a.js", enabled: false)
        #expect(!manager.isModuleEnabled(filename: "a.js"))
        #expect(ws.readSettings()["disabledPlugins"] as? [String] == ["a.js"])

        manager.setModuleEnabled(filename: "a.js", enabled: true)
        #expect(manager.isModuleEnabled(filename: "a.js"))
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

        #expect(engine.commandRegistry["enabled-cmd"] != nil)
        #expect(engine.commandRegistry["disabled-cmd"] == nil)
    }
}
