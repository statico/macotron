import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("ImportGate")
struct ImportGateTests {
    private static let helperSource = "export const answer = 42;\n"

    /// Plugins are IIFE-wrapped, so real plugins load helpers via dynamic import().
    private static let pluginSource = """
        import('plugins/lib/util.js').then(function (m) {
          $$__registerCommand('helper-ok', String(m.answer), function () {});
        }, function (e) {
          $$__registerCommand('helper-blocked', String(e), function () {});
        });
        """

    private func makeWorkspace() throws -> (PluginWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-importgate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        return (ws, dir)
    }

    private func writeHelper(_ ws: PluginWorkspace, source: String = helperSource) throws {
        let libDir = ws.pluginsDir.appending(path: "lib")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        try source.write(to: libDir.appending(path: "util.js"), atomically: true, encoding: .utf8)
    }

    @Test("approved plugin importing an unapproved workdir helper fails; approving the helper unblocks it")
    func gateBlocksUnapprovedWorkdirHelper() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer { PluginTrust.store = previous }

        try writeHelper(ws)
        try Self.pluginSource.write(
            to: ws.pluginsDir.appending(path: "plugin.js"), atomically: true, encoding: .utf8)
        PluginTrust.approve(filename: "plugin.js", source: Self.pluginSource)

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.reloadAll()

        #expect(engine.commandRegistry["plugin.js/helper-ok"] == nil)
        #expect(engine.commandRegistry["plugin.js/helper-blocked"] != nil)

        PluginTrust.approve(filename: "plugins/lib/util.js", source: Self.helperSource)
        manager.reloadAll()

        #expect(engine.commandRegistry["plugin.js/helper-ok"] != nil)
        #expect(engine.commandRegistry["plugin.js/helper-ok"]?.description == "42")
    }

    @Test("session hot reload bypasses the import gate")
    func hotReloadBypassesImportGate() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer { PluginTrust.store = previous }

        try writeHelper(ws)
        try Self.pluginSource.write(
            to: ws.pluginsDir.appending(path: "plugin.js"), atomically: true, encoding: .utf8)

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)
        manager.hotReload = true
        manager.reloadAll()

        #expect(engine.commandRegistry["plugin.js/helper-ok"] != nil)
    }

    @Test("approving reviewed source walks and approves its import chain")
    func approveImportsWalksImportChain() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer { PluginTrust.store = previous }

        let moreSource = "export const bonus = 1;\n"
        let utilSource = "import { bonus } from \"./more.js\";\nexport const answer = 41 + bonus;\n"
        let libDir = ws.pluginsDir.appending(path: "lib")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        try utilSource.write(to: libDir.appending(path: "util.js"), atomically: true, encoding: .utf8)
        try moreSource.write(to: libDir.appending(path: "more.js"), atomically: true, encoding: .utf8)

        PluginTrust.approveImports(in: Self.pluginSource, importerDir: ws.pluginsDir, baseDir: ws.root)

        #expect(store.read(filename: "plugins/lib/util.js") == PluginHash.sha256(source: utilSource))
        #expect(store.read(filename: "plugins/lib/more.js") == PluginHash.sha256(source: moreSource))
    }

    @Test("imports resolved outside the workdir stay ungated")
    func importOutsideWorkdirStaysUngated() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outside = FileManager.default.temporaryDirectory
            .appending(path: "macotron-outside-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let helper = outside.appending(path: "bundled.js")
        try Self.helperSource.write(to: helper, atomically: true, encoding: .utf8)

        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer { PluginTrust.store = previous }

        let engine = Engine()
        engine.moduleBaseDir = ws.root
        engine.evaluate("""
            import('\(helper.path(percentEncoded: false))').then(function (m) {
              globalThis.__answer = m.answer;
            });
            """)

        let (value, _) = engine.evaluate("globalThis.__answer")
        #expect(value == "42")
    }
}
