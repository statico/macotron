// PluginWorkspaceTests.swift — settings round-trip and .gitignore contents
import Foundation
import Testing
@testable import MacotronEngine

@Suite("PluginWorkspace")
struct PluginWorkspaceTests {
    @Test @MainActor
    func settingsRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()

        var settings = ws.readSettings()
        var launcher = settings["launcher"] as? [String: Any] ?? [:]
        launcher["hotkey"] = "ctrl+space"
        settings["launcher"] = launcher
        try ws.writeSettings(settings)

        let reloaded = ws.readSettings()
        let hotkey = (reloaded["launcher"] as? [String: Any])?["hotkey"] as? String
        #expect(hotkey == "ctrl+space")
    }

    @Test @MainActor
    func gitignoreAndAgentDocs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()

        let gitignore = try String(contentsOf: dir.appending(path: ".gitignore"), encoding: .utf8)
        #expect(gitignore.contains("AGENTS.md"))
        #expect(gitignore.contains("CLAUDE.md"))
        #expect(gitignore.contains(".cache/"))

        let agents = try String(contentsOf: dir.appending(path: "AGENTS.md"), encoding: .utf8)
        #expect(agents.hasPrefix(PluginWorkspace.agentsBanner))
        #expect(agents.contains("plugins/*.js"))
        #expect(agents.contains("settings.json"))

        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "plugins").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: ".cache").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "README.md").path(percentEncoded: false)))

        let jsconfig = try String(
            contentsOf: dir.appending(path: ".cache/jsconfig.json"),
            encoding: .utf8
        )
        #expect(jsconfig.contains("checkJs"))
        #expect(jsconfig.contains("../plugins/**/*.js"))
        #expect(jsconfig.contains("macotron.d.ts"))

        #expect(agents.contains("1.0.0"))
        #expect(agents.contains("@macotron needs"))
        #expect(agents.contains("tsc -p .cache --noEmit"))
        #expect(agents.contains("--check"))
    }
}
