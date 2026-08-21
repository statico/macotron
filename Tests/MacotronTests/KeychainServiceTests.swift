// KeychainServiceTests.swift — tests must never write the login io.statico.macotron service
import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Keychain service isolation")
struct KeychainServiceTests {
    init() { KeychainStore.serviceName = "io.statico.macotron.tests" }

    @Test("overridden serviceName routes default writes to the test service")
    func writesUseInjectedService() {
        let account = "macotron.test.\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }

        KeychainStore.write(account: account, value: "v")
        #expect(KeychainStore.read(account: account, service: "io.statico.macotron.tests") == "v")
        #expect(KeychainStore.read(account: account, service: "io.statico.macotron") == nil)
    }

    @Test("trust service name is unchanged")
    func trustServiceUnchanged() {
        #expect(KeychainStore.trustServiceName == "io.statico.macotron.trust")
    }
}
