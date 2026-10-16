// PrefsModule.swift — macotron.prefs: the current user's preference domains (CFPreferences)
import CQuickJS
import Foundation
import MacotronEngine

/// What `defaults read` and `defaults write` reach, without the subprocess:
/// the current user, any host.
public enum Prefs {
    /// `-g` and `NSGlobalDomain` are the global domain, as they are to `defaults`.
    public static func domain(_ name: String) -> CFString {
        name == "-g" || name == "NSGlobalDomain" ? kCFPreferencesAnyApplication : name as CFString
    }

    /// One key, or the whole domain when `key` is nil. Only this domain is
    /// read: an app key does not fall through to the global domain.
    public static func get(_ domain: String, _ key: String?) -> Any? {
        let app = Self.domain(domain)
        // Another process (System Settings, Finder) may have written since we last looked.
        CFPreferencesAppSynchronize(app)
        if let key {
            return CFPreferencesCopyValue(key as CFString, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                .map { PlistValue.toJS($0) }
        }
        let all = CFPreferencesCopyMultiple(nil, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return PlistValue.toJS(all as? [String: Any] ?? [:])
    }

    /// `nil` deletes the key. False when the value is not a property list
    /// (a null inside an array, say) or the write did not reach disk.
    public static func set(_ domain: String, _ key: String, _ value: Any?) -> Bool {
        let app = Self.domain(domain)
        if let value, !PropertyListSerialization.propertyList(value, isValidFor: .binary) { return false }
        CFPreferencesSetValue(key as CFString, value.map { $0 as CFPropertyList }, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

@MainActor
public final class PrefsModule: NativeModule {
    public let name = "prefs"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let prefs = JS_NewObject(ctx)

        JSBridge.fn(ctx, prefs, "get", 2) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1,
                  let domain = JSBridge.toString(ctx, argv[0]) else { return QJS_Null() }
            let key = argc > 1 && !JS_IsUndefined(argv[1]) && !JS_IsNull(argv[1])
                ? JSBridge.toString(ctx, argv[1]) : nil
            return PlistModule.js(ctx, Prefs.get(domain, key))
        }

        JSBridge.fn(ctx, prefs, "set", 3) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 3,
                  let domain = JSBridge.toString(ctx, argv[0]),
                  let key = JSBridge.toString(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "prefs.set requires domain, key, and value")
            }
            if Engine.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            let value: Any? = JS_IsNull(argv[2]) ? nil : JSBridge.jsToSwift(ctx, argv[2])
            return JSBridge.newBool(ctx, Prefs.set(domain, key, value))
        }

        JS_SetPropertyStr(ctx, macotron, "prefs", prefs)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
