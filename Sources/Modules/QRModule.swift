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
            if Engine.isDryRun(ctx) { return QJS_Null() }
            guard let ctx, let argv, argc >= 1, let text = JSBridge.toString(ctx, argv[0]), !text.isEmpty,
                  let png = QRCodes.png(text: text, size: QRModule.size(ctx, argc: argc, argv: argv)) else {
                return QJS_Null()
            }
            return JSBridge.newString(ctx, png.base64EncodedString())
        }, "image", 2))

        JS_SetPropertyStr(ctx, qr, "show", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            if Engine.isDryRun(ctx) { return QJS_Undefined() }
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
        guard let argv, argc >= 2, JS_IsObject(argv[1]),
              let size = JSBridge.int(ctx, argv[1], "size") else { return 256 }
        return min(max(CGFloat(size), 32), QRCodes.maxPixelSize)
    }

    fileprivate static func detect(_ ctx: OpaquePointer?, argc: Int32, argv: UnsafePointer<JSValue>?) -> JSValue {
        guard let ctx, let argv, argc >= 1 else {
            return QJS_ThrowTypeError(ctx, "qr.detect requires { path } or { image }")
        }
        if Engine.isDryRun(ctx) {
            return promise(ctx) { $0(nil) }
        }
        let path = JSBridge.string(ctx, argv[0], "path")
        let image = JSBridge.string(ctx, argv[0], "image")

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
        if Engine.isDryRun(ctx) {
            return promise(ctx) { $0(nil) }
        }
        var camera = false
        var screenshot = true
        var selection = true
        if argc >= 1, let argv, JS_IsObject(argv[0]) {
            camera = JSBridge.bool(ctx, argv[0], "camera") ?? camera
            screenshot = JSBridge.bool(ctx, argv[0], "screenshot") ?? screenshot
            selection = JSBridge.bool(ctx, argv[0], "selection") ?? selection
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

    /// A promise this module settles from the main thread once the picker,
    /// the camera, or the detector comes back with a string (or nothing).
    private static func promise(_ ctx: OpaquePointer, run: (@escaping @Sendable (String?) -> Void) -> Void) -> JSValue {
        let (promise, settle) = JSBridge.deferred(ctx)
        guard !Engine.isDryRun(ctx) else { return promise }
        run { text in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { settle(.of(text)) }
            }
        }
        return promise
    }
}
