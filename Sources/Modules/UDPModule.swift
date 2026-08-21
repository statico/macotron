import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class UDPModule: NativeModule {
    public let name = "udp"

    private let hub = UDPHub()
    private weak var engine: Engine?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__udpModule"] = self
        hub.onMessage = { [weak self] host, port, data in
            DispatchQueue.main.async {
                self?.emit(host: host, port: port, data: data)
            }
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let obj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, obj, "send", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 3 else {
                return JSBridge.newObject(ctx!, ["ok": false, "error": "host, port, data"])
            }
            let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
            if engine.dryRun { return JSBridge.newObject(ctx, ["ok": true]) }
            guard let host = JSBridge.toString(ctx, argv[0]),
                  let data = UDPCodec.encode(JSBridge.jsToSwift(ctx, argv[2])) else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "bad data"])
            }
            let port = Int(JSBridge.toInt32(ctx, argv[1]))
            let hub = (engine.configStore["__udpModule"] as? UDPModule)?.hub
            return JSBridge.newObject(ctx, hub?.send(host: host, port: port, data: data) ?? ["ok": false])
        }, "send", 3))

        JS_SetPropertyStr(ctx, obj, "listen", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else {
                return JSBridge.newObject(ctx!, ["ok": false, "error": "port"])
            }
            let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
            if engine.dryRun { return JSBridge.newObject(ctx, ["ok": true]) }
            let port = Int(JSBridge.toInt32(ctx, argv[0]))
            let hub = (engine.configStore["__udpModule"] as? UDPModule)?.hub
            return JSBridge.newObject(ctx, hub?.listen(port: port) ?? ["ok": false])
        }, "listen", 1))

        JS_SetPropertyStr(ctx, obj, "unlisten", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
            let port = Int(JSBridge.toInt32(ctx, argv[0]))
            (engine.configStore["__udpModule"] as? UDPModule)?.hub.unlisten(port: port)
            return QJS_Undefined()
        }, "unlisten", 1))

        JS_SetPropertyStr(ctx, macotron, "udp", obj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        hub.cleanup()
        engine = nil
    }

    private func emit(host: String, port: Int, data: String) {
        guard let engine, let ctx = engine.context else { return }
        let payload = JSBridge.newObject(ctx, [
            "host": host,
            "port": port,
            "data": data,
        ])
        engine.eventBus.emit("udp:message", engine: engine, data: payload)
        JS_FreeValue(ctx, payload)
    }
}
