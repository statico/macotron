// ScreenModule.swift — macotron.screen: screen capture via ScreenCaptureKit
import AppKit
import CQuickJS
import CoreGraphics
import Foundation
import MacotronEngine
import ScreenCaptureKit
import os

private let logger = Logger(subsystem: "com.macotron", category: "screen")

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
                let sel = JSBridge.getProperty(ctx, argv[0], "selection")
                if !JS_IsUndefined(sel) {
                    selection = JSBridge.toBool(ctx, sel)
                }
                JS_FreeValue(ctx, sel)
            }

            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                if engine.dryRun {
                    return JSBridge.newString(ctx, "")
                }
            }

            if selection {
                var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
                let promise = JS_NewPromiseCapability(ctx, &resolving)
                let resolve = JS_DupValue(ctx, resolving[0])
                let reject = JS_DupValue(ctx, resolving[1])
                JS_FreeValue(ctx, resolving[0])
                JS_FreeValue(ctx, resolving[1])

                guard let opaque else { return promise }
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                nonisolated(unsafe) let capturedCtx = ctx

                Task { @MainActor in
                    let rect = await ScreenRegionPicker.shared.pick()
                    guard let rect else {
                        var value = JSBridge.newString(capturedCtx, "")
                        _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                        engine.drainJobQueue()
                        return
                    }
                    do {
                        let base64 = try await captureRegion(rect)
                        var value = JSBridge.newString(capturedCtx, base64)
                        _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                    } catch {
                        var value = JSBridge.newString(capturedCtx, error.localizedDescription)
                        _ = JS_Call(capturedCtx, reject, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                    }
                    engine.drainJobQueue()
                }
                return promise
            }

            let box = CaptureResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            Task.detached {
                do {
                    box.base64 = try await captureDisplayPNG()
                } catch {
                    box.error = "Screen capture failed: \(error.localizedDescription)"
                }
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + 5)
            if waitResult == .timedOut {
                logger.error("Screen capture timed out")
                return JSBridge.newString(ctx, "")
            }

            if let error = box.error {
                logger.error("Screen capture error: \(error)")
                return JSBridge.newString(ctx, "")
            }

            return JSBridge.newString(ctx, box.base64 ?? "")
        }, "capture", 1))

        JS_SetPropertyStr(ctx, screenObj, "pickColor",
                          JS_NewCFunction(ctx, { ctx, _, _, _ -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                if engine.dryRun {
                    return QJS_Null()
                }
            }

            var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolving)
            let resolve = JS_DupValue(ctx, resolving[0])
            let reject = JS_DupValue(ctx, resolving[1])
            JS_FreeValue(ctx, resolving[0])
            JS_FreeValue(ctx, resolving[1])

            guard let opaque else { return promise }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            nonisolated(unsafe) let capturedCtx = ctx

            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                let color = await NSColorSampler().sample()
                let point = NSEvent.mouseLocation
                let value: JSValue
                if let color, let rgb = color.usingColorSpace(.sRGB) {
                    value = JSBridge.anyToJS(capturedCtx, [
                        "hex": String(format: "#%02X%02X%02X",
                                      Int((rgb.redComponent * 255).rounded()),
                                      Int((rgb.greenComponent * 255).rounded()),
                                      Int((rgb.blueComponent * 255).rounded())),
                        "r": Int((rgb.redComponent * 255).rounded()),
                        "g": Int((rgb.greenComponent * 255).rounded()),
                        "b": Int((rgb.blueComponent * 255).rounded()),
                        "x": Int(point.x.rounded()),
                        "y": Int(point.y.rounded()),
                    ] as [String: Any])
                } else {
                    value = QJS_Null()
                }
                var arg = value
                _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &arg)
                JS_FreeValue(capturedCtx, arg)
                JS_FreeValue(capturedCtx, resolve)
                JS_FreeValue(capturedCtx, reject)
                engine.drainJobQueue()
            }
            return promise
        }, "pickColor", 0))

        JS_SetPropertyStr(ctx, macotron, "screen", screenObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}

private func captureDisplayPNG(displayID: CGDirectDisplayID? = nil) async throws -> String {
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

private func captureRegion(_ cocoa: CGRect) async throws -> String {
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
