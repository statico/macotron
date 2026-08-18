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

    private static let serviceName = KeychainStore.serviceName

    public init() {}

    // MARK: - Static Helpers

    /// Write a value to the Keychain. Usable from Swift without a JS context.
    public static func writeToKeychain(key: String, value: String) {
        KeychainStore.write(account: key, value: value)
    }

    /// Read a value from the Keychain by key name. Usable from Swift without a JS context.
    public static func readFromKeychain(key: String) -> String? {
        KeychainStore.read(account: key)
    }

    /// Delete a value from the Keychain. Usable from Swift without a JS context.
    public static func deleteFromKeychain(key: String) {
        KeychainStore.delete(account: key)
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

            if let value = KeychainStore.read(account: key) {
                return JSBridge.newString(ctx, value)
            }
            return QJS_Null()
        }, "get", 1))

        // --- set(key, value) ---
        JS_SetPropertyStr(ctx, keychainObj, "set", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]),
                  let value = JSBridge.toString(ctx, argv[1]) else { return QJS_Undefined() }

            KeychainStore.write(account: key, value: value)
            return QJS_Undefined()
        }, "set", 2))

        // --- delete(key) ---
        JS_SetPropertyStr(ctx, keychainObj, "delete", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            KeychainStore.delete(account: key)
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
