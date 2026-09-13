import CQuickJS
import Foundation
import IOKit.hid
import MacotronEngine
import os.log

private let logger = Logger(subsystem: "io.statico.macotron", category: "hid")

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

        JSBridge.fn(ctx, hid, "list", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, HIDDevices.list(HIDModule.filter(ctx, argc: argc, argv: argv, at: 0)))
        }

        JSBridge.fn(ctx, hid, "open", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Null() }
            guard let hub = HIDModule.hub(ctx),
                  let row = hub.open(HIDModule.filter(ctx, argc: argc, argv: argv, at: 0)) else {
                return QJS_Null()
            }
            return JSBridge.newObject(ctx, row)
        }

        JSBridge.fn(ctx, hid, "close", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            HIDModule.hub(ctx)?.close(id)
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, hid, "sendOutput", 3) { ctx, _, argc, argv in
            HIDModule.send(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeOutput)
        }

        JSBridge.fn(ctx, hid, "sendFeature", 3) { ctx, _, argc, argv in
            HIDModule.send(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeFeature)
        }

        // Waits on the interrupt pipe like `hid_read`. `readInputReport` is the
        // control GetReport that this used to be — a different transfer, which
        // most devices never answer.
        JSBridge.fn(ctx, hid, "readInput", 2) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let handle = JSBridge.deferred(ctx, dryRun: NSNull())
            guard let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
                  let hub = HIDModule.hub(ctx) else {
                handle.settle(.failure("missing id"))
                return handle.promise
            }
            var timeout = 1.0
            if argc >= 2, JS_IsObject(argv[1]),
               let opts = JSBridge.jsToSwift(ctx, argv[1]) as? [String: Any],
               let ms = Coerce.int(opts["timeout"]) {
                timeout = max(Double(ms), 0) / 1000
            }
            hub.read(id, timeout: timeout, settle: handle.settle)
            return handle.promise
        }

        JSBridge.fn(ctx, hid, "readInputReport", 2) { ctx, _, argc, argv in
            HIDModule.read(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeInput)
        }

        JSBridge.fn(ctx, hid, "readFeature", 3) { ctx, _, argc, argv in
            HIDModule.read(ctx, argc: argc, argv: argv, type: kIOHIDReportTypeFeature)
        }

        JSBridge.fn(ctx, hid, "listen", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return JSBridge.newObject(ctx!, ["ok": false, "error": "missing id"])
            }
            guard let hub = HIDModule.hub(ctx) else {
                return JSBridge.newObject(ctx, ["ok": false, "error": "unavailable"])
            }
            return JSBridge.newObject(ctx, hub.listen(id))
        }

        JSBridge.fn(ctx, hid, "unlisten", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]) else {
                return QJS_Undefined()
            }
            HIDModule.hub(ctx)?.unlisten(id)
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, hid, "reportDescriptor", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let id = JSBridge.toString(ctx, argv[0]),
                  let device = HIDModule.hub(ctx)?.device(id),
                  let bytes = HIDDevices.reportDescriptor(device) else {
                return QJS_Null()
            }
            return JSBridge.newArray(ctx, bytes)
        }

        JS_SetPropertyStr(ctx, macotron, "hid", hid)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        hub.closeAll()
    }

    fileprivate static func hub(_ ctx: OpaquePointer) -> HIDHub? {
        let module: HIDModule? = Engine.module(ctx, "__hidModule")
        if module == nil { logger.error("hid: module lookup failed; configStore lost __hidModule") }
        return module?.hub
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
        let padded = HIDBytes.pad(bytes, length: Coerce.int(opts["length"]))
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
                reportID = Coerce.int(opts["reportId"]) ?? 0
            }
        }
        let length = Coerce.int(opts["length"]) ?? (HIDDevices.maxReport(device, type) + 1)
        guard let bytes = HIDDevices.getReport(device, type: type, reportID: reportID, length: length) else {
            return QJS_Null()
        }
        return JSBridge.newArray(ctx, bytes.map { Int($0) })
    }
}
