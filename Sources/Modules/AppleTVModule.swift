import CQuickJS
import Foundation
import MacotronEngine

enum AppleTVRemote {
    static let types = ["_companion-link._tcp", "_airplay._tcp"]

    /// A browse runs for its whole timeout, so one per key press would leave the
    /// remote unresponsive between presses. Apple TVs do not come and go by the
    /// second, so a recent result is reused.
    static let browseTTL: TimeInterval = 30

    // ponytail: one lock for the whole cache; it guards two fields and is only
    // taken around a browse, so contention is not worth a finer scheme.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: [[String: Any]] = []
    nonisolated(unsafe) private static var browsedAt: Date?

    /// Runs the browse on the calling thread when the cache is cold, so call it
    /// from a promise's queue rather than the main thread.
    static func devices() -> [[String: Any]] {
        lock.lock()
        if let browsedAt, Date().timeIntervalSince(browsedAt) < browseTTL, !cached.isEmpty {
            defer { lock.unlock() }
            return cached
        }
        lock.unlock()

        let rows = merge(BonjourBrowse.browse(types: types, timeout: 1.5, dryRun: false))
        lock.lock()
        cached = rows
        browsedAt = Date()
        lock.unlock()
        return rows
    }

    static func merge(_ services: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var out: [[String: Any]] = []
        for s in services {
            let host = s["host"] as? String ?? ""
            let port = s["port"] as? Int ?? 0
            guard !host.isEmpty, port > 0 else { continue }
            let id = "\(host):\(port)"
            guard seen.insert(id).inserted else { continue }
            out.append([
                "id": id,
                "name": s["name"] as? String ?? "",
                "host": host,
                "port": port,
                "type": s["type"] as? String ?? "",
            ])
        }
        return out
    }

    static func send(id: String, command: String, devices: [[String: Any]], dryRun: Bool) -> [String: Any] {
        if dryRun { return ["ok": true] }
        guard devices.contains(where: { ($0["id"] as? String) == id }) else {
            return ["ok": false, "error": "No Apple TV"]
        }
        _ = command
        // ponytail: Companion pairing if a real TV is in hand
        return ["ok": false, "error": "not paired"]
    }
}

@MainActor
public final class AppleTVModule: NativeModule {
    public let name = "appletv"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let obj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, obj, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(AppleTVRemote.devices().map { $0 as Any })
            }
        }, "list", 0))

        JS_SetPropertyStr(ctx, obj, "send", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let dry: [String: Any] = ["ok": true]
            guard let argv, argc >= 2,
                  let id = JSBridge.toString(ctx, argv[0]),
                  let command = JSBridge.toString(ctx, argv[1]) else {
                return JSBridge.promise(ctx, dryRun: dry) {
                    .value(["ok": false, "error": "No Apple TV"] as [String: Any])
                }
            }
            return JSBridge.promise(ctx, dryRun: dry) {
                .value(AppleTVRemote.send(
                    id: id, command: command, devices: AppleTVRemote.devices(), dryRun: false
                ))
            }
        }, "send", 2))

        JS_SetPropertyStr(ctx, macotron, "appletv", obj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
