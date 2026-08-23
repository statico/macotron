import AppKit
import CQuickJS
import Foundation
import MacotronEngine

public struct LauncherHit {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: String
    public let image: NSImage?
}

@MainActor
public final class LauncherModule: NativeModule {
    public let name = "launcher"

    private weak var engine: Engine?
    private var callbacks: [String: JSValue] = [:]
    private var hits: [String: [LauncherHit]] = [:]
    private var icons: [String: NSImage] = [:]
    private var queries: [String: JSValue] = [:]

    /// Live results are stored under `provider + liveSuffix` so they reuse the
    /// static parsing and callback bookkeeping without leaking into `allHits`,
    /// which feeds fuzzy matching and favorites.
    private static let liveSuffix = "\u{1}live"

    public init() {}

    public func allHits() -> [LauncherHit] {
        hits.keys.sorted()
            .filter { !$0.hasSuffix(Self.liveSuffix) }
            .flatMap { hits[$0] ?? [] }
    }

    /// Asks every registered `launcher.query` provider what it makes of the
    /// current text. Runs on each keystroke, so providers must return fast.
    public func liveHits(query: String) -> [LauncherHit] {
        guard let engine, let ctx = engine.context, !queries.isEmpty else { return [] }
        var out: [LauncherHit] = []
        for provider in queries.keys.sorted() {
            guard let callback = queries[provider] else { continue }
            var arg: JSValue = JSBridge.newString(ctx, query)
            let fn = JS_DupValue(ctx, callback)
            let result = JS_Call(ctx, fn, QJS_Undefined(), 1, &arg)
            JS_FreeValue(ctx, fn)
            JS_FreeValue(ctx, arg)
            let bucket = provider + Self.liveSuffix
            replace(provider: bucket, items: result, ctx: ctx)
            JS_FreeValue(ctx, result)
            out.append(contentsOf: hits[bucket] ?? [])
        }
        return out
    }

    public func run(_ id: String) -> Bool {
        guard let engine, let ctx = engine.context, let cb = callbacks[id] else { return false }
        let fn = JS_DupValue(ctx, cb)
        _ = JS_Call(ctx, fn, QJS_Undefined(), 0, nil)
        JS_FreeValue(ctx, fn)
        engine.drainJobQueue()
        return true
    }

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__launcherModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let launcher = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, launcher, "set", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let mod = engine.configStore["__launcherModule"] as? LauncherModule,
                  let provider = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            mod.replace(provider: provider, items: argv[1], ctx: ctx)
            return QJS_Undefined()
        }, "set", 2))

        JS_SetPropertyStr(ctx, launcher, "query", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let mod = engine.configStore["__launcherModule"] as? LauncherModule,
                  let provider = JSBridge.toString(ctx, argv[0]),
                  JS_IsFunction(ctx, argv[1]) else {
                return QJS_Undefined()
            }
            if let old = mod.queries.removeValue(forKey: provider) {
                JS_FreeValue(ctx, old)
            }
            mod.queries[provider] = JS_DupValue(ctx, argv[1])
            return QJS_Undefined()
        }, "query", 2))

        JS_SetPropertyStr(ctx, launcher, "remove", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            guard let mod = engine.configStore["__launcherModule"] as? LauncherModule,
                  let provider = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            mod.drop(provider: provider, ctx: ctx)
            mod.dropQuery(provider: provider, ctx: ctx)
            return QJS_Undefined()
        }, "remove", 1))

        JS_SetPropertyStr(ctx, macotron, "launcher", launcher)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        guard let ctx = engine?.context else { return }
        for (_, cb) in callbacks {
            JS_FreeValue(ctx, cb)
        }
        callbacks.removeAll()
        for (_, cb) in queries {
            JS_FreeValue(ctx, cb)
        }
        queries.removeAll()
        hits.removeAll()
        engine = nil
    }

    private func drop(provider: String, ctx: OpaquePointer) {
        let prefix = "launcher:\(provider)/"
        for key in callbacks.keys where key.hasPrefix(prefix) {
            if let cb = callbacks.removeValue(forKey: key) {
                JS_FreeValue(ctx, cb)
            }
        }
        hits[provider] = nil
    }

    private func dropQuery(provider: String, ctx: OpaquePointer) {
        if let callback = queries.removeValue(forKey: provider) {
            JS_FreeValue(ctx, callback)
        }
        drop(provider: provider + Self.liveSuffix, ctx: ctx)
    }

    private func replace(provider: String, items: JSValue, ctx: OpaquePointer) {
        drop(provider: provider, ctx: ctx)
        guard JS_IsArray(items) else { return }
        let lenVal = JS_GetPropertyStr(ctx, items, "length")
        let len = JSBridge.toInt32(ctx, lenVal)
        JS_FreeValue(ctx, lenVal)
        var list: [LauncherHit] = []
        list.reserveCapacity(Int(len))
        for idx in 0..<len {
            let elem = JS_GetPropertyUint32(ctx, items, UInt32(idx))
            defer { JS_FreeValue(ctx, elem) }
            guard JS_IsObject(elem) else { continue }

            let idVal = JSBridge.getProperty(ctx, elem, "id")
            let rawId = JSBridge.toString(ctx, idVal) ?? "\(idx)"
            JS_FreeValue(ctx, idVal)
            let id = "launcher:\(provider)/\(rawId)"

            let titleVal = JSBridge.getProperty(ctx, elem, "title")
            let title = JSBridge.toString(ctx, titleVal) ?? rawId
            JS_FreeValue(ctx, titleVal)

            let subtitleVal = JSBridge.getProperty(ctx, elem, "subtitle")
            let subtitle = JSBridge.isUndefined(subtitleVal) || JSBridge.isNull(subtitleVal)
                ? "" : (JSBridge.toString(ctx, subtitleVal) ?? "")
            JS_FreeValue(ctx, subtitleVal)

            let kindVal = JSBridge.getProperty(ctx, elem, "kind")
            let kind = JSBridge.isUndefined(kindVal) || JSBridge.isNull(kindVal)
                ? "" : (JSBridge.toString(ctx, kindVal) ?? "")
            JS_FreeValue(ctx, kindVal)

            let appVal = JSBridge.getProperty(ctx, elem, "app")
            let app = JSBridge.isUndefined(appVal) || JSBridge.isNull(appVal)
                ? nil : JSBridge.toString(ctx, appVal)
            JS_FreeValue(ctx, appVal)

            let sfVal = JSBridge.getProperty(ctx, elem, "sfSymbol")
            let sfSymbol = JSBridge.isUndefined(sfVal) || JSBridge.isNull(sfVal)
                ? nil : JSBridge.toString(ctx, sfVal)
            JS_FreeValue(ctx, sfVal)

            let onClickVal = JSBridge.getProperty(ctx, elem, "onClick")
            if JS_IsFunction(ctx, onClickVal) {
                callbacks[id] = JS_DupValue(ctx, onClickVal)
            }
            JS_FreeValue(ctx, onClickVal)

            list.append(LauncherHit(
                id: id,
                title: title,
                subtitle: subtitle,
                kind: kind,
                image: icon(app: app, sfSymbol: sfSymbol)
            ))
        }
        hits[provider] = list
    }

    private func icon(app: String?, sfSymbol: String?) -> NSImage? {
        if let app, !app.isEmpty {
            if let cached = icons[app] { return cached }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else {
                return symbol(sfSymbol)
            }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 20, height: 20)
            icons[app] = image
            return image
        }
        return symbol(sfSymbol)
    }

    private func symbol(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty,
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        image.size = NSSize(width: 20, height: 20)
        image.isTemplate = true
        return image
    }
}
