// KeychainModule.swift — macotron.keychain: secure credential storage via Security.framework
import CQuickJS
import Foundation
import MacotronEngine

/// Trust-ledger accounts are off limits even though the ledger lives in a
/// separate Keychain service — defense in depth against forged entries.
private func isLedgerAccount(_ key: String) -> Bool {
    key.hasPrefix("macotron.plugin.hash.")
}

@MainActor
public final class KeychainModule: NativeModule {
    public let name = "keychain"

    public init() {}

    // MARK: - NativeModule

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let keychainObj = JS_NewObject(ctx)

        // --- get(key) → string | null ---
        JSBridge.fn(ctx, keychainObj, "get", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Null() }
            guard let key = JSBridge.toString(ctx, argv[0]), !isLedgerAccount(key) else { return QJS_Null() }

            if let value = KeychainStore.read(account: key) {
                return JSBridge.newString(ctx, value)
            }
            return QJS_Null()
        }

        // --- set(key, value) ---
        JSBridge.fn(ctx, keychainObj, "set", 2) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]), !isLedgerAccount(key),
                  let value = JSBridge.toString(ctx, argv[1]) else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Undefined() }

            KeychainStore.write(account: key, value: value)
            return QJS_Undefined()
        }

        // --- delete(key) ---
        JSBridge.fn(ctx, keychainObj, "delete", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]), !isLedgerAccount(key) else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Undefined() }

            KeychainStore.delete(account: key)
            return QJS_Undefined()
        }

        // --- has(key) → bool ---
        JSBridge.fn(ctx, keychainObj, "has", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            guard let key = JSBridge.toString(ctx, argv[0]), !isLedgerAccount(key) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, KeychainStore.read(account: key) != nil)
        }

        JS_SetPropertyStr(ctx, macotron, "keychain", keychainObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
