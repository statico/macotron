// ScreenModule.swift — macotron.screen: screen capture via ScreenCaptureKit
import AppKit
import CQuickJS
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

        // macotron.screen.capture(opts?) -> base64 PNG string
        JS_SetPropertyStr(ctx, screenObj, "capture",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            let box = CaptureResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            Task.detached {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: true
                    )
                    guard let display = content.displays.first else {
                        box.error = "No display found"
                        semaphore.signal()
                        return
                    }

                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = Int(display.width)
                    config.height = Int(display.height)
                    config.pixelFormat = kCVPixelFormatType_32BGRA

                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    )

                    // Convert CGImage to PNG data
                    let bitmapRep = NSBitmapImageRep(cgImage: image)
                    if let pngData = bitmapRep.representation(
                        using: .png, properties: [:]
                    ) {
                        box.base64 = pngData.base64EncodedString()
                    } else {
                        box.error = "Failed to encode PNG"
                    }
                } catch {
                    box.error = "Screen capture failed: \(error.localizedDescription)"
                }
                semaphore.signal()
            }

            // Wait with a timeout of 5 seconds
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

        JS_SetPropertyStr(ctx, macotron, "screen", screenObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
