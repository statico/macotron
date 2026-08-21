// PluginSettingsTests.swift — plugin option resolution, password refs, Keychain storage
import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Plugin Settings")
struct PluginSettingsTests {
    init() { KeychainStore.serviceName = "io.statico.macotron.tests" }

    // MARK: - KeychainStore

    @Test("KeychainStore write/read/delete roundtrip")
    func keychainRoundtrip() {
        let account = "macotron.test.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }

        #expect(KeychainStore.read(account: account) == nil)

        KeychainStore.write(account: account, value: "value1")
        #expect(KeychainStore.read(account: account) == "value1")

        KeychainStore.write(account: account, value: "value2")
        #expect(KeychainStore.read(account: account) == "value2")

        KeychainStore.delete(account: account)
        #expect(KeychainStore.read(account: account) == nil)
    }

    @Test("Plugin option account id format")
    func pluginOptionAccountFormat() {
        #expect(KeychainStore.pluginOptionAccount(filename: "chat.js", key: "apiKey")
            == "macotron.plugin.chat.js.apiKey")
    }

    // MARK: - $$__module resolution

    /// Compares two JSON strings as parsed dictionaries so key order does not matter.
    /// $$__module builds its result from a Swift dictionary whose iteration order is
    /// randomized per process, so string equality on the JSON output is flaky.
    private func assertJSONEqual(_ actual: String?, _ expected: String) throws {
        let actual = try #require(actual)
        let actualData = Data(actual.utf8)
        let expectedData = Data(expected.utf8)
        let actualObj = try JSONSerialization.jsonObject(with: actualData)
        let expectedObj = try JSONSerialization.jsonObject(with: expectedData)
        #expect((actualObj as AnyObject).isEqual(to: expectedObj as Any),
                "JSON mismatch: actual=\(actual) expected=\(expected)")
    }

    @Test("$$__module resolves defaults and user overrides")
    func moduleResolvesDefaultsAndOverrides() throws {
        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        engine.moduleSettings = ["test.js": ["greeting": "hi"]]

        let (result, error) = engine.evaluate("""
            var opts = $$__module({ options: {
                greeting: { type: "string", label: "Greeting", default: "hello" },
                count: { type: "number", label: "Count", default: 3 },
            }});
            JSON.stringify(opts);
        """)
        #expect(error == nil)
        try assertJSONEqual(result, #"{"count":3,"greeting":"hi"}"#)
    }

    @Test("$$__module resolves password option from Keychain ref")
    func moduleResolvesPasswordFromKeychain() throws {
        let account = KeychainStore.pluginOptionAccount(filename: "test.js", key: "apiKey")
        KeychainStore.write(account: account, value: "secret-value-123")
        defer { KeychainStore.delete(account: account) }

        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        engine.moduleSettings = ["test.js": ["apiKey": account]]

        let (result, error) = engine.evaluate("""
            var opts = $$__module({ options: {
                apiKey: { type: "password", label: "API Key", required: true },
            }});
            JSON.stringify(opts);
        """)
        #expect(error == nil)
        try assertJSONEqual(result, #"{"apiKey":"secret-value-123"}"#)
    }

    @Test("$$__module returns empty string for unset password")
    func moduleUnsetPasswordIsEmpty() throws {
        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        engine.moduleSettings = [:]

        let (result, error) = engine.evaluate("""
            var opts = $$__module({ options: {
                apiKey: { type: "password", label: "API Key" },
            }});
            JSON.stringify(opts);
        """)
        #expect(error == nil)
        try assertJSONEqual(result, #"{"apiKey":""}"#)
    }

    @Test("$$__module returns empty string when Keychain ref has no value")
    func moduleDanglingPasswordRefIsEmpty() throws {
        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        engine.moduleSettings = ["test.js": ["apiKey": "macotron.plugin.test.js.apiKey.missing.\(UUID().uuidString)"]]

        let (result, error) = engine.evaluate("""
            var opts = $$__module({ options: {
                apiKey: { type: "password", label: "API Key" },
            }});
            JSON.stringify(opts);
        """)
        #expect(error == nil)
        try assertJSONEqual(result, #"{"apiKey":""}"#)
    }

    @Test("$$__module ignores default for password options")
    func modulePasswordIgnoresDefault() throws {
        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        engine.moduleSettings = [:]

        let (result, error) = engine.evaluate("""
            var opts = $$__module({ options: {
                apiKey: { type: "password", label: "API Key", default: "should-not-leak" },
            }});
            JSON.stringify(opts);
        """)
        #expect(error == nil)
        try assertJSONEqual(result, #"{"apiKey":""}"#)
    }

    @Test("$$__module records permissions")
    func moduleRecordsPermissions() {
        let engine = Engine()
        engine.currentEvaluatingFile = "test.js"
        let (_, error) = engine.evaluate("""
            $$__module({ title: "OCR", permissions: ["screenRecording", "accessibility"] });
        """)
        #expect(error == nil)
        #expect(engine.declaredPermissions == ["screenRecording", "accessibility"])
    }

    // MARK: - ModuleManager secret storage

    @Test("saveModuleSecret stores ref in settings and secret in Keychain; clear removes both")
    func moduleManagerSecretLifecycle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-ws-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ws = PluginWorkspace(root: dir)
        try ws.ensureReady()
        let manager = ModuleManager(engine: Engine(), workspace: ws)
        let account = KeychainStore.pluginOptionAccount(filename: "chat.js", key: "apiKey")
        defer { KeychainStore.delete(account: account) }

        manager.saveModuleSecret(filename: "chat.js", key: "apiKey", secret: "sk-ant-xyz")

        // settings.json holds the ref, not the secret
        let stored = manager.loadModuleSettings()["chat.js"]?["apiKey"] as? String
        #expect(stored == account)
        #expect(KeychainStore.read(account: account) == "sk-ant-xyz")

        let onDisk = try String(contentsOf: ws.settingsFile, encoding: .utf8)
        #expect(onDisk.contains(account))
        #expect(!onDisk.contains("sk-ant-xyz"))

        manager.clearModuleSecret(filename: "chat.js", key: "apiKey")
        #expect(manager.loadModuleSettings()["chat.js"]?["apiKey"] == nil)
        #expect(KeychainStore.read(account: account) == nil)
    }
}

