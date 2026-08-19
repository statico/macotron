// KeychainStore.swift — static Keychain primitives shared by the engine and modules
import Foundation
import Security
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "keychain-store")

/// Generic-password Keychain storage. Lives in MacotronEngine so `$$__module`
/// can resolve `password` option refs without depending on the Modules target.
public enum KeychainStore {
    public static let serviceName = "io.statico.macotron"

    /// Stable Keychain account id for a plugin's password option.
    /// Example: `macotron.plugin.chat.js.apiKey`
    public static func pluginOptionAccount(filename: String, key: String) -> String {
        "macotron.plugin.\(filename).\(key)"
    }

    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
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

    public static func write(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
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

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("KeychainStore.delete: SecItemDelete failed with status \(status)")
        }
    }
}
