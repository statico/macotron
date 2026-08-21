// KeychainStore.swift — static Keychain primitives shared by the engine and modules
import Foundation
import Security
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "keychain-store")

/// Generic-password Keychain storage. Lives in MacotronEngine so `$$__module`
/// can resolve `password` option refs without depending on the Modules target.
public enum KeychainStore {
    /// Default Keychain service. Tests override this to `io.statico.macotron.tests`
    /// so they never write real login-Keychain items. Set once before any use;
    /// `nonisolated(unsafe)` because Swift 6 forbids mutable statics otherwise.
    public nonisolated(unsafe) static var serviceName = "io.statico.macotron"

    /// Host-only service for the plugin trust ledger. Never exposed to
    /// `macotron.keychain.*`, so plugins cannot forge or wipe approvals.
    public static let trustServiceName = "io.statico.macotron.trust"

    /// Stable Keychain account id for a plugin's password option.
    /// Example: `macotron.plugin.chat.js.apiKey`
    public static func pluginOptionAccount(filename: String, key: String) -> String {
        "macotron.plugin.\(filename).\(key)"
    }

    public static func read(account: String, service: String = serviceName) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return nil
    }

    public static func write(account: String, value: String, service: String = serviceName) {
        guard let data = value.data(using: .utf8) else { return }

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("KeychainStore.write: SecItemAdd failed with status \(addStatus)")
            }
        } else if status != errSecSuccess {
            logger.error("KeychainStore.write: SecItemUpdate failed with status \(status)")
        }
    }

    public static func delete(account: String, service: String = serviceName) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("KeychainStore.delete: SecItemDelete failed with status \(status)")
        }
    }

    /// All account ids stored under `service`.
    public static func accounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
