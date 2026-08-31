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
    public let path: String
    /// Set by a provider that answers any query rather than a name, so its rows
    /// sort below what the user actually typed.
    public let secondary: Bool
}

@MainActor
public final class LauncherModule: NativeModule {
    public let name = "launcher"

    private weak var engine: Engine?
    private var callbacks: [String: JSValue] = [:]
    private var hits: [String: [LauncherHit]] = [:]
    private var icons: [String: NSImage] = [:]
    private var queries: [String: JSValue] = [:]
    private var resolvers: [String: JSValue] = [:]
    private var secondary: Set<String> = []
    private var awaitGlue: JSValue?
    private var push: JSValue?
    /// The text the newest round of live queries was asked about. A promise
    /// settles against the query it answered, not against a counter: every
    /// `liveHits` call used to bump a counter, so a refresh triggered by any
    /// other provider invalidated an answer to the query still on screen and
    /// the launcher waited out another whole round trip for the same rows.
    private var currentQuery = ""
    private var isCollecting = false
    /// The query each live bucket last answered. Rows are only served while the
    /// query on screen is related to the one they answered — typing forward or
    /// backward along the same text — so a bucket that answered "desktop" is
    /// never dressed up as an answer to "applications".
    private var answered: [String: String] = [:]
    /// Bumped per liveHits round so only the newest watchdog fires.
    private var watchdogGeneration = 0

    /// Called when a provider answers after `liveHits` has already returned, so
    /// the launcher can refresh a list that would otherwise stay stale.
    public var onLiveUpdate: (() -> Void)?

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
    /// current text. A provider may return rows directly or a Promise of them;
    /// a Promise is never waited on, it pushes through `replace` when it
    /// settles and `onLiveUpdate` tells the launcher to ask again.
    public func liveHits(query: String) -> [LauncherHit] {
        guard let engine, let ctx = engine.context, !queries.isEmpty else { return [] }
        currentQuery = query
        isCollecting = true
        defer { isCollecting = false }
        let buckets = queries.keys.sorted().map { $0 + Self.liveSuffix }
        for provider in queries.keys.sorted() {
            guard let callback = queries[provider] else { continue }
            let arg = JSBridge.newString(ctx, query)
            let bucket = provider + Self.liveSuffix
            let result = engine.callJS(
                callback, [arg],
                budget: Engine.inputBudget,
                label: "launcher query \(provider)"
            )
            JS_FreeValue(ctx, arg)
            guard let result else {
                drop(provider: bucket, ctx: ctx)
                answered[bucket] = query
                continue
            }
            if isThenable(ctx, result) {
                // The rows already in the bucket answer an older keystroke, and
                // they stay until this promise settles. Clearing them here empties
                // the bucket one tick before the answer arrives -- and this method
                // returns the bucket -- so a provider that is always async would
                // never show a row, and every settle would trigger another round.
                awaitRows(ctx, engine: engine, promise: result, bucket: bucket)
            } else {
                replace(provider: bucket, items: result, ctx: ctx)
                answered[bucket] = query
            }
            JS_FreeValue(ctx, result)
        }
        if buckets.contains(where: { answered[$0] != query }) {
            armWatchdog(for: query)
        }
        return buckets.flatMap { bucket in
            related(answered[bucket], to: query) ? hits[bucket] ?? [] : []
        }
    }

    /// Old rows stay on screen while the text is still the same thought —
    /// extended or trimmed — and vanish the moment it is a different one.
    private func related(_ answeredQuery: String?, to query: String) -> Bool {
        guard let answeredQuery else { return false }
        return query.hasPrefix(answeredQuery) || answeredQuery.hasPrefix(query)
    }

    /// A settled promise is the only thing that refreshes the launcher, and a
    /// settle can be lost: a plugin job over its budget is interrupted, and an
    /// interrupted promise reaction is consumed without ever running, so
    /// nothing would ask again. One second of silence on the same query means
    /// asking again, which fires fresh promises and heals the buckets.
    private func armWatchdog(for query: String) {
        watchdogGeneration += 1
        let generation = watchdogGeneration
        // A runloop timer, not asyncAfter: it fires even when the main queue
        // is occupied by whoever is pumping the runloop.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, generation == self.watchdogGeneration,
                      query == self.currentQuery,
                      self.queries.keys.contains(where: { self.answered[$0 + Self.liveSuffix] != query })
                else { return }
                self.onLiveUpdate?()
            }
        }
    }

    private func isThenable(_ ctx: OpaquePointer, _ value: JSValue) -> Bool {
        guard JS_IsObject(value) else { return false }
        let then = JSBridge.getProperty(ctx, value, "then")
        defer { JS_FreeValue(ctx, then) }
        return JS_IsFunction(ctx, then)
    }

    private func awaitRows(_ ctx: OpaquePointer, engine: Engine, promise: JSValue, bucket: String) {
        guard let glue = awaitGlue, let push else { return }
        let args = [
            JS_DupValue(ctx, push),
            JS_DupValue(ctx, promise),
            JSBridge.newString(ctx, bucket),
            JSBridge.newString(ctx, currentQuery),
        ]
        if let result = engine.callJS(glue, args, label: "launcher await \(bucket)") {
            JS_FreeValue(ctx, result)
        }
        for arg in args { JS_FreeValue(ctx, arg) }
    }

    private func fingerprint(_ bucket: String) -> [String] {
        (hits[bucket] ?? []).map { "\($0.id)\u{1}\($0.title)\u{1}\($0.subtitle)" }
    }

    public func run(_ id: String) -> Bool {
        guard let engine, let ctx = engine.context else { return false }
        let parsed = Self.split(id)
        var callback = callbacks[id]
        if callback == nil, let parsed {
            callback = callbacks["launcher:\(parsed.provider)\(Self.liveSuffix)/\(parsed.rowId)"]
        }
        if let callback {
            let fn = JS_DupValue(ctx, callback)
            if let result = engine.callJS(fn, label: "launcher run \(id)") {
                JS_FreeValue(ctx, result)
            }
            JS_FreeValue(ctx, fn)
            return true
        }
        // The row answered an older keystroke or died with a restart, so the
        // provider gets to replay it from the id alone.
        guard let parsed, let resolver = resolvers[parsed.provider] else { return false }
        let arg = JSBridge.newString(ctx, parsed.rowId)
        if let result = engine.callJS(
            resolver, [arg],
            budget: Engine.inputBudget,
            label: "launcher resolve \(parsed.provider)"
        ) {
            JS_FreeValue(ctx, result)
        }
        JS_FreeValue(ctx, arg)
        return true
    }

    /// A row id is often a file path, so only the first "/" after the prefix
    /// separates the provider from the row.
    static func split(_ id: String) -> (provider: String, rowId: String)? {
        guard id.hasPrefix("launcher:") else { return nil }
        let rest = id.dropFirst("launcher:".count)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return (stripLive(String(rest[rest.startIndex..<slash])),
                String(rest[rest.index(after: slash)...]))
    }

    static func stripLive(_ provider: String) -> String {
        provider.hasSuffix(liveSuffix) ? String(provider.dropLast(liveSuffix.count)) : provider
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
            guard let mod: LauncherModule = Engine.module(ctx, "__launcherModule"),
                  let provider = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            mod.replace(provider: provider, items: argv[1], ctx: ctx)
            return QJS_Undefined()
        }, "set", 2))

        JS_SetPropertyStr(ctx, launcher, "query", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let mod: LauncherModule = Engine.module(ctx, "__launcherModule"),
                  let provider = JSBridge.toString(ctx, argv[0]),
                  JS_IsFunction(ctx, argv[1]) else {
                return QJS_Undefined()
            }
            if let old = mod.queries.removeValue(forKey: provider) {
                JS_FreeValue(ctx, old)
            }
            mod.queries[provider] = JS_DupValue(ctx, argv[1])
            if let old = mod.resolvers.removeValue(forKey: provider) {
                JS_FreeValue(ctx, old)
            }
            mod.secondary.remove(provider)
            if argc >= 3, JS_IsObject(argv[2]) {
                let run = JSBridge.getProperty(ctx, argv[2], "run")
                if JS_IsFunction(ctx, run) {
                    mod.resolvers[provider] = JS_DupValue(ctx, run)
                }
                JS_FreeValue(ctx, run)
                if JSBridge.bool(ctx, argv[2], "secondary") == true {
                    mod.secondary.insert(provider)
                }
            }
            return QJS_Undefined()
        }, "query", 3))

        JS_SetPropertyStr(ctx, launcher, "remove", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let mod: LauncherModule = Engine.module(ctx, "__launcherModule"),
                  let provider = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            mod.drop(provider: provider, ctx: ctx)
            mod.dropQuery(provider: provider, ctx: ctx)
            return QJS_Undefined()
        }, "remove", 1))

        push = JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 3 else { return QJS_Undefined() }
            guard let engine = Engine.of(ctx) else { return QJS_Undefined() }
            guard let mod = engine.configStore["__launcherModule"] as? LauncherModule,
                  let bucket = JSBridge.toString(ctx, argv[0]),
                  JSBridge.toString(ctx, argv[2]) == mod.currentQuery else {
                return QJS_Undefined()
            }
            let before = mod.fingerprint(bucket)
            mod.replace(provider: bucket, items: argv[1], ctx: ctx)
            mod.answered[bucket] = mod.currentQuery
            // Refreshing on an unchanged answer would ask the provider again,
            // which would resolve again: the same rows end the round trip.
            if !mod.isCollecting, before != mod.fingerprint(bucket) {
                mod.onLiveUpdate?()
            }
            return QJS_Undefined()
        }, "push", 3)

        // A rejected provider hands `replace` a non-array, which clears the
        // bucket, so one handler covers both outcomes.
        engine.evaluate("""
            globalThis.__macotronLauncherAwait = function (push, promise, bucket, asked) {
                var settle = function (rows) { push(bucket, rows, asked); };
                Promise.resolve(promise).then(settle, settle);
            };
            """, filename: "<launcher-await>")
        awaitGlue = JSBridge.getProperty(ctx, global, "__macotronLauncherAwait")
        let atom = JS_NewAtom(ctx, "__macotronLauncherAwait")
        _ = JS_DeleteProperty(ctx, global, atom, 0)
        JS_FreeAtom(ctx, atom)

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
        for (_, cb) in resolvers {
            JS_FreeValue(ctx, cb)
        }
        resolvers.removeAll()
        secondary.removeAll()
        if let glue = awaitGlue { JS_FreeValue(ctx, glue) }
        awaitGlue = nil
        if let push { JS_FreeValue(ctx, push) }
        push = nil
        hits.removeAll()
        answered.removeAll()
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
        if let resolver = resolvers.removeValue(forKey: provider) {
            JS_FreeValue(ctx, resolver)
        }
        secondary.remove(provider)
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
        // The id handed out drops the internal live bucket marker so a saved
        // shortcut survives the launcher closing; callbacks stay keyed by bucket.
        let shown = Self.stripLive(provider)
        let isSecondary = secondary.contains(shown)
        for idx in 0..<len {
            let elem = JS_GetPropertyUint32(ctx, items, UInt32(idx))
            defer { JS_FreeValue(ctx, elem) }
            guard JS_IsObject(elem) else { continue }

            let rawId = JSBridge.string(ctx, elem, "id") ?? "\(idx)"
            let id = "launcher:\(provider)/\(rawId)"
            let shownId = "launcher:\(shown)/\(rawId)"

            let title = JSBridge.string(ctx, elem, "title") ?? rawId
            let subtitle = JSBridge.string(ctx, elem, "subtitle") ?? ""
            let kind = JSBridge.string(ctx, elem, "kind") ?? ""
            let app = JSBridge.string(ctx, elem, "app")
            let sfSymbol = JSBridge.string(ctx, elem, "sfSymbol")
            let path = JSBridge.string(ctx, elem, "path") ?? ""

            let onClickVal = JSBridge.getProperty(ctx, elem, "onClick")
            if JS_IsFunction(ctx, onClickVal) {
                callbacks[id] = JS_DupValue(ctx, onClickVal)
            }
            JS_FreeValue(ctx, onClickVal)

            list.append(LauncherHit(
                id: shownId,
                title: title,
                subtitle: subtitle,
                kind: kind,
                image: icon(app: app, path: path, sfSymbol: sfSymbol),
                path: path,
                secondary: isSecondary
            ))
        }
        hits[provider] = list
    }

    private func icon(app: String?, path: String, sfSymbol: String?) -> NSImage? {
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
        // File rows are few and their paths all differ, so caching them would
        // only grow a dictionary keyed for bundle ids.
        if !path.isEmpty {
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: 20, height: 20)
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
