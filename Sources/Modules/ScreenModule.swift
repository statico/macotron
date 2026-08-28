// ScreenModule.swift — macotron.screen: screen capture via ScreenCaptureKit
import AppKit
import CQuickJS
import CoreGraphics
import Foundation
import MacotronEngine
import ScreenCaptureKit

private final class CaptureResultBox: @unchecked Sendable {
    var base64: String?
    var error: String?
}

@MainActor
public final class ScreenModule: NativeModule {
    public let name = "screen"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let screenObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, screenObj, "capture",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var selection = false
            if argc >= 1, let argv, !JS_IsUndefined(argv[0]), JS_IsObject(argv[0]), !JS_IsString(argv[0]) {
                selection = JSBridge.bool(ctx, argv[0], "selection") ?? false
            }

            if selection {
                if Engine.isDryRun(ctx) { return JSBridge.newString(ctx, "") }
                let (promise, settle) = JSBridge.deferred(ctx)
                Task { @MainActor in
                    guard let rect = await ScreenRegionPicker.shared.pick() else {
                        settle(.value(""))
                        return
                    }
                    do {
                        settle(.value(try await captureRegion(rect)))
                    } catch {
                        settle(.failure(error.localizedDescription))
                    }
                }
                return promise
            }

            // ScreenCaptureKit is async-only, so someone has to wait for it: the
            // promise's worker thread, never the main thread.
            return JSBridge.promise(ctx, dryRun: "") {
                let box = CaptureResultBox()
                let done = DispatchSemaphore(value: 0)
                Task.detached {
                    do {
                        box.base64 = try await captureDisplayPNG()
                    } catch {
                        box.error = error.localizedDescription
                    }
                    done.signal()
                }
                done.wait()
                if let error = box.error { return .failure("screen.capture failed: \(error)") }
                return .value(box.base64 ?? "")
            }
        }, "capture", 1))

        JS_SetPropertyStr(ctx, screenObj, "pickColor",
                          JS_NewCFunction(ctx, { ctx, _, _, _ -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            if Engine.isDryRun(ctx) { return QJS_Null() }

            let (promise, settle) = JSBridge.deferred(ctx)
            Task { @MainActor in
                AppActivation.activate("screen capture")
                let color = await NSColorSampler().sample()
                let point = NSEvent.mouseLocation
                guard let color, let rgb = color.usingColorSpace(.sRGB) else {
                    settle(.value(NSNull()))
                    return
                }
                settle(.value([
                    "hex": String(format: "#%02X%02X%02X",
                                  Int((rgb.redComponent * 255).rounded()),
                                  Int((rgb.greenComponent * 255).rounded()),
                                  Int((rgb.blueComponent * 255).rounded())),
                    "r": Int((rgb.redComponent * 255).rounded()),
                    "g": Int((rgb.greenComponent * 255).rounded()),
                    "b": Int((rgb.blueComponent * 255).rounded()),
                    "x": Int(point.x.rounded()),
                    "y": Int(point.y.rounded()),
                ] as [String: Any]))
            }
            return promise
        }, "pickColor", 0))

        JS_SetPropertyStr(ctx, macotron, "screen", screenObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}

func captureDisplayPNG(displayID: CGDirectDisplayID? = nil) async throws -> String {
    let image = try await captureDisplay(displayID: displayID)
    guard let png = pngBase64(image) else {
        throw NSError(domain: "macotron.screen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    return png
}

private func captureDisplay(displayID: CGDirectDisplayID? = nil) async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let display: SCDisplay
    if let displayID, let match = content.displays.first(where: { $0.displayID == displayID }) {
        display = match
    } else if let first = content.displays.first {
        display = first
    } else {
        throw NSError(domain: "macotron.screen", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display found"])
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(display.width)
    config.height = Int(display.height)
    config.pixelFormat = kCVPixelFormatType_32BGRA
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
}

func captureRegion(_ cocoa: CGRect) async throws -> String {
    let screen = NSScreen.screens.first { $0.frame.intersects(cocoa) }
        ?? NSScreen.main
        ?? NSScreen.screens[0]
    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    let image = try await captureDisplay(displayID: displayID)
    let scaleX = CGFloat(image.width) / screen.frame.width
    let scaleY = CGFloat(image.height) / screen.frame.height
    let crop = CGRect(
        x: (cocoa.minX - screen.frame.minX) * scaleX,
        y: (screen.frame.maxY - cocoa.maxY) * scaleY,
        width: cocoa.width * scaleX,
        height: cocoa.height * scaleY
    ).integral
    let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let clipped = crop.intersection(bounds)
    guard !clipped.isNull, !clipped.isEmpty, let cropped = image.cropping(to: clipped) else {
        throw NSError(domain: "macotron.screen", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not crop selection"])
    }
    guard let png = pngBase64(cropped) else {
        throw NSError(domain: "macotron.screen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    return png
}

private func pngBase64(_ image: CGImage) -> String? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.base64EncodedString()
}
