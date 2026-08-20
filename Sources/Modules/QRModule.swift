import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class QRModule: NativeModule {
    public let name = "qr"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let qr = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, qr, "detect", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            QRModule.detect(ctx, argc: argc, argv: argv)
        }, "detect", 1))

        JS_SetPropertyStr(ctx, qr, "scan", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            QRModule.scan(ctx, argc: argc, argv: argv)
        }, "scan", 1))

        JS_SetPropertyStr(ctx, qr, "image", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let text = JSBridge.toString(ctx, argv[0]), !text.isEmpty,
                  let png = QRCodes.png(text: text, size: QRModule.size(ctx, argc: argc, argv: argv)) else {
                return QJS_Null()
            }
            return JSBridge.newString(ctx, png.base64EncodedString())
        }, "image", 2))

        JS_SetPropertyStr(ctx, qr, "show", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let text = JSBridge.toString(ctx, argv[0]), !text.isEmpty,
                  let png = QRCodes.png(text: text, size: QRModule.size(ctx, argc: argc, argv: argv)),
                  let image = NSImage(data: png) else {
                return QJS_Undefined()
            }
            QRWindow.show(image)
            return QJS_Undefined()
        }, "show", 2))

        JS_SetPropertyStr(ctx, macotron, "qr", qr)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    fileprivate static func size(_ ctx: OpaquePointer, argc: Int32, argv: UnsafePointer<JSValue>?) -> CGFloat {
        guard let argv, argc >= 2, JS_IsObject(argv[1]) else { return 256 }
        let val = JSBridge.getProperty(ctx, argv[1], "size")
        defer { JS_FreeValue(ctx, val) }
        if JSBridge.isUndefined(val) || JSBridge.isNull(val) { return 256 }
        return CGFloat(max(JSBridge.toInt32(ctx, val), 32))
    }

    fileprivate static func detect(_ ctx: OpaquePointer?, argc: Int32, argv: UnsafePointer<JSValue>?) -> JSValue {
        guard let ctx, let argv, argc >= 1 else {
            return QJS_ThrowTypeError(ctx, "qr.detect requires { path } or { image }")
        }
        let opts = argv[0]
        let pathVal = JSBridge.getProperty(ctx, opts, "path")
        let imageVal = JSBridge.getProperty(ctx, opts, "image")
        let path = JSBridge.isUndefined(pathVal) ? nil : JSBridge.toString(ctx, pathVal)
        let image = JSBridge.isUndefined(imageVal) ? nil : JSBridge.toString(ctx, imageVal)
        JS_FreeValue(ctx, pathVal)
        JS_FreeValue(ctx, imageVal)

        let url: URL?
        let data: Data?
        if let path, !path.isEmpty {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            data = nil
        } else if let image, let decoded = QRCodes.decodeBase64(image) {
            url = nil
            data = decoded
        } else {
            return QJS_ThrowTypeError(ctx, "qr.detect requires a valid path or base64 image")
        }
        return promise(ctx) { resolve in
            DispatchQueue.global(qos: .userInitiated).async {
                if let url {
                    resolve(QRCodes.detect(url: url))
                } else if let data {
                    resolve(QRCodes.detect(data: data))
                } else {
                    resolve(nil)
                }
            }
        }
    }

    fileprivate static func scan(_ ctx: OpaquePointer?, argc: Int32, argv: UnsafePointer<JSValue>?) -> JSValue {
        guard let ctx else { return QJS_Undefined() }
        var camera = false
        var screenshot = true
        var selection = true
        if argc >= 1, let argv, JS_IsObject(argv[0]) {
            let cam = JSBridge.getProperty(ctx, argv[0], "camera")
            if !JSBridge.isUndefined(cam), !JSBridge.isNull(cam) { camera = JSBridge.toBool(ctx, cam) }
            JS_FreeValue(ctx, cam)
            let shot = JSBridge.getProperty(ctx, argv[0], "screenshot")
            if !JSBridge.isUndefined(shot), !JSBridge.isNull(shot) { screenshot = JSBridge.toBool(ctx, shot) }
            JS_FreeValue(ctx, shot)
            let sel = JSBridge.getProperty(ctx, argv[0], "selection")
            if !JSBridge.isUndefined(sel), !JSBridge.isNull(sel) { selection = JSBridge.toBool(ctx, sel) }
            JS_FreeValue(ctx, sel)
        }
        if camera { screenshot = false }
        return promise(ctx) { resolve in
            Task { @MainActor in
                if camera {
                    resolve(await QRCameraPicker.shared.pick())
                    return
                }
                if screenshot {
                    if selection {
                        guard let rect = await ScreenRegionPicker.shared.pick() else {
                            resolve(nil)
                            return
                        }
                        let png = try? await captureRegion(rect)
                        resolve(png.flatMap { QRCodes.decodeBase64($0) }.flatMap { QRCodes.detect(data: $0) })
                    } else {
                        let png = try? await captureDisplayPNG()
                        resolve(png.flatMap { QRCodes.decodeBase64($0) }.flatMap { QRCodes.detect(data: $0) })
                    }
                    return
                }
                resolve(nil)
            }
        }
    }

    private static func promise(_ ctx: OpaquePointer, run: (@escaping @Sendable (String?) -> Void) -> Void) -> JSValue {
        var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
        let promise = JS_NewPromiseCapability(ctx, &resolving)
        let resolveFn = JS_DupValue(ctx, resolving[0])
        let rejectFn = JS_DupValue(ctx, resolving[1])
        JS_FreeValue(ctx, resolving[0])
        JS_FreeValue(ctx, resolving[1])
        let opaque = JS_GetContextOpaque(ctx)
        let engine = opaque.map { Unmanaged<Engine>.fromOpaque($0).takeUnretainedValue() }
        nonisolated(unsafe) let capturedCtx = ctx
        run { text in
            DispatchQueue.main.async {
                var value = text.map { JSBridge.newString(capturedCtx, $0) } ?? QJS_Null()
                _ = JS_Call(capturedCtx, resolveFn, QJS_Undefined(), 1, &value)
                JS_FreeValue(capturedCtx, value)
                JS_FreeValue(capturedCtx, resolveFn)
                JS_FreeValue(capturedCtx, rejectFn)
                engine?.drainJobQueue()
            }
        }
        return promise
    }
}
