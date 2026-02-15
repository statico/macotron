// KeychainModule.swift — macotron.keychain: secure credential storage via Security.framework
import CQuickJS
import Foundation
import MacotronEngine
import Security
import os

private let logger = Logger(subsystem: "com.macotron", category: "keychain")

@MainActor
public final class KeychainModule: NativeModule {
    public let name = "keychain"

    private static let serviceName = "com.macotron"

    public init() {}

    // MARK: - Static Helpers

    /// Read a value from the Keychain by key name. Usable from Swift without a JS context.
    public static func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
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

    // MARK: - NativeModule

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let keychainObj = JS_NewObject(ctx)

        // --- get(key) → string | null ---
        JS_SetPropertyStr(ctx, keychainObj, "get", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Null() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Null() }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainModule.serviceName,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecSuccess, let data = result as? Data,
               let str = String(data: data, encoding: .utf8) {
                return JSBridge.newString(ctx, str)
            }
            return QJS_Null()
        }, "get", 1))

        // --- set(key, value) ---
        JS_SetPropertyStr(ctx, keychainObj, "set", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]),
                  let value = JSBridge.toString(ctx, argv[1]) else { return QJS_Undefined() }

            guard let valueData = value.data(using: .utf8) else { return QJS_Undefined() }

            // Try to update first
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainModule.serviceName,
                kSecAttrAccount as String: key,
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: valueData,
            ]

            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

            if updateStatus == errSecItemNotFound {
                // Item doesn't exist yet -- add it
                var addQuery = searchQuery
                addQuery[kSecValueData as String] = valueData
                let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
                if addStatus != errSecSuccess {
                    logger.error("keychain.set: SecItemAdd failed with status \(addStatus)")
                }
            } else if updateStatus != errSecSuccess {
                logger.error("keychain.set: SecItemUpdate failed with status \(updateStatus)")
            }

            return QJS_Undefined()
        }, "set", 2))

        // --- delete(key) ---
        JS_SetPropertyStr(ctx, keychainObj, "delete", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainModule.serviceName,
                kSecAttrAccount as String: key,
            ]

            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("keychain.delete: SecItemDelete failed with status \(status)")
            }

            return QJS_Undefined()
        }, "delete", 1))

        // --- has(key) → bool ---
        JS_SetPropertyStr(ctx, keychainObj, "has", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return JSBridge.newBool(ctx, false) }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainModule.serviceName,
                kSecAttrAccount as String: key,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            let status = SecItemCopyMatching(query as CFDictionary, nil)
            return JSBridge.newBool(ctx, status == errSecSuccess)
        }, "has", 1))

        JS_SetPropertyStr(ctx, macotron, "keychain", keychainObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
