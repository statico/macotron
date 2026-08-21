// TrustLedgerTests.swift — host-only trust ledger: service split + keychain module isolation
import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("TrustLedger")
struct TrustLedgerTests {
    @Test("KeychainHashStore keeps hashes out of the plugin-visible keychain service")
    func hashStoreUsesTrustService() {
        let store = KeychainHashStore()
        let name = "trust-test-\(UUID().uuidString).js"
        defer { store.delete(filename: name) }

        store.write(filename: name, hash: "h1")
        #expect(store.read(filename: name) == "h1")
        #expect(KeychainStore.read(account: KeychainHashStore.account(name)) == nil)
        #expect(KeychainStore.read(
            account: KeychainHashStore.account(name),
            service: "io.statico.macotron.trust") == "h1")

        store.delete(filename: name)
        #expect(store.read(filename: name) == nil)
    }

    @Test("KeychainHashStore.hasAnyHashes sees ledger entries")
    func hasAnyHashesSeesLedger() {
        let store = KeychainHashStore()
        let name = "trust-test-\(UUID().uuidString).js"
        defer { store.delete(filename: name) }

        store.write(filename: name, hash: "h1")
        #expect(store.hasAnyHashes())
    }

    @Test("plugin keychain.delete/get/set cannot touch the trust ledger")
    func keychainModuleCannotTouchLedger() {
        let engine = Engine()
        engine.addModule(KeychainModule())
        engine.registerAllModules()

        let store = KeychainHashStore()
        let name = "foo-\(UUID().uuidString).js"
        defer { store.delete(filename: name) }
        store.write(filename: name, hash: "h1")
        let account = KeychainHashStore.account(name)

        engine.evaluate("macotron.keychain.delete(\"\(account)\")")
        #expect(store.read(filename: name) == "h1")

        let (got, _) = engine.evaluate("String(macotron.keychain.get(\"\(account)\"))")
        #expect(got == "null")

        engine.evaluate("macotron.keychain.set(\"\(account)\", \"evil\")")
        #expect(store.read(filename: name) == "h1")
        #expect(KeychainStore.read(account: account) == nil)

        let (has, _) = engine.evaluate("String(macotron.keychain.has(\"\(account)\"))")
        #expect(has == "false")
    }
}
