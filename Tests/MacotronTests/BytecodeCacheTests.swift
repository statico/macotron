import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("BytecodeCache")
struct BytecodeCacheTests {
    private func makeWorkspace() throws -> (PluginWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-bccache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        return (ws, dir)
    }

    private let goodSource = "$$__registerCommand('good-cmd', 'good', function(){});"

    @Test("planted bytecode not matching source hash must not execute")
    func plantedBytecodeDoesNotExecute() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try goodSource
            .write(to: ws.pluginsDir.appending(path: "good.js"), atomically: true, encoding: .utf8)

        let previous = PluginTrust.store
        PluginTrust.store = MemoryHashStore()
        defer { PluginTrust.store = previous }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)

        let evil = Engine.isolatedPlugin("$$__registerCommand('evil-cmd', 'evil', function(){});")
        let evilBC = try #require(engine.compileToBytecode(evil, filename: "evil"))
        try evilBC.write(to: ws.cacheDir.appending(path: "good.js.iife.bc"))
        let wrongHash = PluginHash.sha256(source: "not-the-approved-source")
        try evilBC.write(to: ws.cacheDir.appending(path: "good.js.\(wrongHash).iife.bc"))

        manager.reloadAll()

        #expect(!engine.commandRegistry.keys.contains { $0.hasSuffix("/evil-cmd") })
        #expect(engine.commandRegistry.keys.contains { $0.hasSuffix("/good-cmd") })
    }

    @Test("cache write is keyed by source hash and deletes stale siblings")
    func cacheWriteKeyedBySourceHashDeletesSiblings() throws {
        let (ws, dir) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        try goodSource
            .write(to: ws.pluginsDir.appending(path: "good.js"), atomically: true, encoding: .utf8)

        let previous = PluginTrust.store
        PluginTrust.store = MemoryHashStore()
        defer { PluginTrust.store = previous }

        let engine = Engine()
        let manager = ModuleManager(engine: engine, workspace: ws)

        try Data().write(to: ws.cacheDir.appending(path: "good.js.iife.bc"))
        try Data().write(to: ws.cacheDir.appending(path: "good.js.deadbeef.iife.bc"))

        manager.reloadAll()

        let expected = "good.js.\(PluginHash.sha256(source: goodSource)).iife.bc"
        let caches = try FileManager.default
            .contentsOfDirectory(atPath: ws.cacheDir.path(percentEncoded: false))
            .filter { $0.hasSuffix(".iife.bc") }
        #expect(caches == [expected])
    }
}
