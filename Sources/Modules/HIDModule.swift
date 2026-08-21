import CQuickJS
import Foundation
import IOKit.hid
import MacotronEngine

@MainActor
public final class HIDModule: NativeModule {
    public let name = "hid"
    public let moduleVersion = 1

    private let hub = HIDHub()

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        hub.engine = engine
        engine.configStore["__hidModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let hid = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, hid, "list", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, HIDDevices.list(HIDModule.filter(ctx, argc: argc, argv: argv, at: 0)))
        }, "list", 1))

        JS_SetPropertyStr(ctx, hid, "open", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Null() }
            guard let hub = HIDModule.hub(ctx),
                  let row = hub.open(HIDModule.filter(ctx, argc: argc, argv: argv, at: 0)) else {
                return QJS_Null()
            }
            return JSBridge.newObject(ctx, row)
        }, "open", 1))

        JS_SetPropertyStr(ctx, hid, "close", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            HIDModule.hub(ctx)?.close(id)
            return QJS_Undefined()
        }, "close", 1))

        JS_SetPropertyStr(ctx, hid, "sendOutput", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            HIDModule.send(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeOutput)
        }, "sendOutput", 3))

        JS_SetPropertyStr(ctx, hid, "sendFeature", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            HIDModule.send(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeFeature)
        }, "sendFeature", 3))

        JS_SetPropertyStr(ctx, hid, "readInput", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            HIDModule.read(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeInput)
        }, "readInput", 2))

        JS_SetPropertyStr(ctx, hid, "readFeature", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            HIDModule.read(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeFeature)
        }, "readFeature", 3))

        JS_SetPropertyStr(ctx, hid, "listen", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newObject(ctx!, ["ok": false, "error": "missing id"])
            }
            guard let hub = HIDModule.hub(ctx) else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "unavailable"])
            }
            return JSBridge.newObject(ctx, hub.listen(id))
        }, "listen", 1))

        JS_SetPropertyStr(ctx, hid, "unlisten", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            HIDModule.hub(ctx)?.unlisten(id)
            return QJS_Undefined()
        }, "unlisten", 1))

        JS_SetPropertyStr(ctx, hid, "reportDescriptor", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
                  let device = HIDModule.hub(ctx)?.device(id),
                  let bytes = HIDDevices.reportDescriptor(device) else {
                return QJS_Null()
            }
            return JSBridge.newArray(ctx, bytes)
        }, "reportDescriptor", 1))

        JS_SetPropertyStr(ctx, macotron, "hid", hid)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        hub.closeAll()
    }

    fileprivate static func hub(_ ctx: OpaquePointer) -> HIDHub? {
        let engine = Unmanaged<Engine>.fromOpaque(JS_GetContextOpaque(ctx)).takeUnretainedValue()
        return (engine.configStore["__hidModule"] as? HIDModule)?.hub
    }

    fileprivate static func filter(_ ctx: OpaquePointer, argc: Int32, argv: UnsafePointer<JSValue>?, at index: Int32) -> HIDFilter {
        guard let argv, argc > index else { return HIDFilter() }
        let val = argv[Int(index)]
        if JSBridge.isUndefined(val) || JSBridge.isNull(val) { return HIDFilter() }
        if JS_IsString(val), let s = JSBridge.toString(ctx, val) {
            let pair = HIDFilter.parseVidPid(s)
            return HIDFilter(vendorID: pair.vendorID, productID: pair.productID)
        }
        guard let dict = JSBridge.jsToSwift(ctx, val) as? [String: Any] else { return HIDFilter() }
        return HIDFilter(dict)
    }

    fileprivate static func send(
        _ ctx: OpaquePointer?,
        argc: Int32,
        argv: UnsafePointer<JSValue>?,
        type: IOHIDReportType
    ) -> JSValue {
        guard let ctx, let argv, argc >= 2, let id = JSBridge.toString(ctx, argv[0]) else {
            return JSBridge.newObject(ctx!, ["ok": false, "error": "missing id"])
        }
        if Engine.isDryRun(ctx) { return JSBridge.newObject(ctx, ["ok": true, "written": 0]) }
        guard let bytes = HIDBytes.parse(JSBridge.jsToSwift(ctx, argv[1])) else {
            return JSBridge.newObject(ctx, ["ok": false, "error": "bad data"])
        }
        let opts = argc >= 3 ? (JSBridge.jsToSwift(ctx, argv[2]) as? [String: Any] ?? [:]) : [:]
        let padded = HIDBytes.pad(bytes, length: HIDFilter.int(opts["length"]))
        guard let device = hub(ctx)?.device(id) else {
            return JSBridge.newObject(ctx, ["ok": false, "error": "not open"])
        }
        let result = HIDDevices.setReport(device, type: type, bytes: padded)
        var row: [String: Any] = ["ok": result.ok, "written": result.written]
        if let error = result.error { row["error"] = error }
        return JSBridge.newObject(ctx, row)
    }

    fileprivate static func read(
        _ ctx: OpaquePointer?,
        argc: Int32,
        argv: UnsafePointer<JSValue>?,
        type: IOHIDReportType
    ) -> JSValue {
        guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
              let device = hub(ctx)?.device(id) else {
            return QJS_Null()
        }
        var reportID = 0
        var opts: [String: Any] = [:]
        if argc >= 2 {
            let second = argv[1]
            if JS_IsNumber(second) {
                reportID = Int(JSBridge.toInt32(ctx, second))
                if argc >= 3 { opts = JSBridge.jsToSwift(ctx, argv[2]) as? [String: Any] ?? [:] }
            } else if JS_IsObject(second) {
                opts = JSBridge.jsToSwift(ctx, second) as? [String: Any] ?? [:]
                reportID = HIDFilter.int(opts["reportId"]) ?? 0
            }
        }
        let length = HIDFilter.int(opts["length"]) ?? (HIDDevices.maxReport(device, type) + 1)
        guard let bytes = HIDDevices.getReport(device, type: type, reportID: reportID, length: length) else {
            return QJS_Null()
        }
        return JSBridge.newArray(ctx, bytes.map { Int($0) })
    }
}
