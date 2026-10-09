// PluginKeychainTests.swift — per-plugin keychain accounts and the legacy fallback
import Foundation
import Testing
@testable import Modules

@Suite("Plugin keychain")
struct PluginKeychainTests {
    final class Memory: @unchecked Sendable {
        var items: [String: String]
        init(_ items: [String: String]) { self.items = items }
        var store: PluginKeychain.Store {
            PluginKeychain.Store(read: { self.items[$0] }, write: { self.items[$0] = $1 })
        }
    }

    @Test("accounts are per plugin")
    func accountsArePerPlugin() {
        #expect(PluginKeychain.account(file: "a.js", key: "token") == "macotron.keychain/a.js/token")
        #expect(PluginKeychain.account(file: "a.js", key: "t") != PluginKeychain.account(file: "b.js", key: "t"))
    }

    @Test("a plugin reads its own key, not another plugin's")
    func ownKeyOnly() {
        let memory = Memory([PluginKeychain.account(file: "b.js", key: "token"): "b-secret"])
        #expect(PluginKeychain.get(file: "a.js", key: "token", migrate: true, store: memory.store) == nil)
        #expect(PluginKeychain.get(file: "b.js", key: "token", migrate: true, store: memory.store) == "b-secret")
    }

    @Test("a legacy shared key is copied into the plugin's own account")
    func legacyMigrates() {
        let memory = Memory(["token": "old"])
        #expect(PluginKeychain.get(file: "a.js", key: "token", migrate: true, store: memory.store) == "old")
        #expect(memory.items[PluginKeychain.account(file: "a.js", key: "token")] == "old")
    }

    @Test("a dry run reads a legacy key without copying it")
    func dryRunDoesNotMigrate() {
        let memory = Memory(["token": "old"])
        #expect(PluginKeychain.get(file: "a.js", key: "token", migrate: false, store: memory.store) == "old")
        #expect(memory.items.count == 1)
    }

    @Test("host accounts are never read as legacy keys", arguments: [
        "macotron.plugin.chat.js.apiKey",
        "macotron.plugin.hash.chat.js",
        "macotron.keychain/b.js/token",
    ])
    func hostAccountsAreOffLimits(_ key: String) {
        let memory = Memory([key: "secret"])
        #expect(PluginKeychain.get(file: "a.js", key: key, migrate: true, store: memory.store) == nil)
    }
}
