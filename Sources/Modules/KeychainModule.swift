// KeychainModule.swift — macotron.keychain: secure credential storage via Security.framework
import CQuickJS
import Foundation
import MacotronEngine

/// Each plugin's keys live under its own account prefix, so one plugin cannot
/// read another's secrets by guessing the key.
enum PluginKeychain {
    struct Store: Sendable {
        var read: @Sendable (String) -> String?
        var write: @Sendable (String, String) -> Void

        static let keychain = Store(
            read: { KeychainStore.read(account: $0) },
            write: { KeychainStore.write(account: $0, value: $1) }
        )
    }

    /// Filenames cannot contain "/", so no file and key pair can pass for another.
    static func account(file: String, key: String) -> String {
        "macotron.keychain/\(file)/\(key)"
    }

    /// Keys used to be shared by every plugin and stored as typed. Anything
    /// under "macotron." is the host's — password options, the trust ledger,
    /// other plugins' keys — and was never a plugin key.
    static func legacyAccount(_ key: String) -> String? {
        key.hasPrefix("macotron.") ? nil : key
    }

    /// The plugin's own value, else a pre-namespacing value under the same key,
    /// copied over so the next read finds it. `migrate` is off in dry runs.
    // ponytail: the legacy read hands a shared key to whichever plugin asks
    // first; drop it a couple of releases after 0.8.
    static func get(file: String, key: String, migrate: Bool, store: Store = .keychain) -> String? {
        let account = account(file: file, key: key)
        if let value = store.read(account) { return value }
        guard let legacy = legacyAccount(key), let value = store.read(legacy) else { return nil }
        if migrate { store.write(account, value) }
        return value
    }
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
            guard let ctx, let argv, argc >= 1, let key = JSBridge.toString(ctx, argv[0]),
                  let file = Engine.of(ctx)?.secretOwner(ctx),
                  let value = PluginKeychain.get(file: file, key: key, migrate: !Engine.isDryRun(ctx))
            else { return QJS_Null() }
            return JSBridge.newString(ctx, value)
        }

        // --- set(key, value) ---
        JSBridge.fn(ctx, keychainObj, "set", 2) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2, !Engine.isDryRun(ctx),
                  let key = JSBridge.toString(ctx, argv[0]),
                  let value = JSBridge.toString(ctx, argv[1]),
                  let file = Engine.of(ctx)?.secretOwner(ctx) else { return QJS_Undefined() }
            KeychainStore.write(account: PluginKeychain.account(file: file, key: key), value: value)
            return QJS_Undefined()
        }

        // --- delete(key) ---
        JSBridge.fn(ctx, keychainObj, "delete", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1, !Engine.isDryRun(ctx),
                  let key = JSBridge.toString(ctx, argv[0]),
                  let file = Engine.of(ctx)?.secretOwner(ctx) else { return QJS_Undefined() }
            KeychainStore.delete(account: PluginKeychain.account(file: file, key: key))
            return QJS_Undefined()
        }

        // --- has(key) → bool ---
        JSBridge.fn(ctx, keychainObj, "has", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1, let key = JSBridge.toString(ctx, argv[0]),
                  let file = Engine.of(ctx)?.secretOwner(ctx) else { return JSBridge.newBool(ctx, false) }
            let found = PluginKeychain.get(file: file, key: key, migrate: !Engine.isDryRun(ctx)) != nil
            return JSBridge.newBool(ctx, found)
        }

        JS_SetPropertyStr(ctx, macotron, "keychain", keychainObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
