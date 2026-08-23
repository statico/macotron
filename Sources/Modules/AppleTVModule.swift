import CQuickJS
import Foundation
import MacotronEngine

enum AppleTVRemote {
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

    private var devices: [[String: Any]] = []
    private var browsedAt: Date?

    /// A browse parks the main thread in a nested run loop for its whole
    /// timeout, so repeating one per key press beachballs the machine. Apple TVs
    /// do not come and go by the second; reuse a recent result.
    private static let browseTTL: TimeInterval = 30

    fileprivate func cachedDevices() -> [[String: Any]]? {
        guard let browsedAt, Date().timeIntervalSince(browsedAt) < Self.browseTTL,
              !devices.isEmpty else { return nil }
        return devices
    }

    fileprivate func store(_ rows: [[String: Any]]) {
        devices = rows
        browsedAt = Date()
    }

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__appletvModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let obj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, obj, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
            let module = engine.configStore["__appletvModule"] as? AppleTVModule
            if let cached = module?.cachedDevices() {
                return JSBridge.newArray(ctx, cached.map { $0 as Any })
            }
            let rows = AppleTVRemote.merge(BonjourBrowse.browse(
                types: ["_companion-link._tcp", "_airplay._tcp"],
                timeout: 1.5,
                dryRun: engine.dryRun
            ))
            module?.store(rows)
            return JSBridge.newArray(ctx, rows.map { $0 as Any })
        }, "list", 0))

        JS_SetPropertyStr(ctx, obj, "send", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2,
                  let id = JSBridge.toString(ctx, argv[0]),
                  let command = JSBridge.toString(ctx, argv[1]) else {
                return JSBridge.newObject(ctx!, ["ok": false, "error": "No Apple TV"])
            }
            let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
            if engine.dryRun { return JSBridge.newObject(ctx, ["ok": true]) }
            let module = engine.configStore["__appletvModule"] as? AppleTVModule
            var devices = module?.cachedDevices() ?? []
            if devices.isEmpty {
                devices = AppleTVRemote.merge(BonjourBrowse.browse(
                    types: ["_companion-link._tcp", "_airplay._tcp"],
                    timeout: 1.5,
                    dryRun: false
                ))
                module?.store(devices)
            }
            return JSBridge.newObject(ctx, AppleTVRemote.send(id: id, command: command, devices: devices, dryRun: false))
        }, "send", 2))

        JS_SetPropertyStr(ctx, macotron, "appletv", obj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
