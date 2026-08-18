// DisplayModule.swift — macotron.display: enumerate connected displays
import AppKit
import CQuickJS
import Darwin
import Foundation
import MacotronEngine
import QuartzCore

private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

@MainActor
public final class DisplayModule: NativeModule {
    public let name = "display"
    public let moduleVersion = 1

    private var xdrWindow: NSWindow?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__displayModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let displayObj = JS_NewObject(ctx)

        // macotron.display.list() -> array of {id, width, height, main: bool}
        JS_SetPropertyStr(ctx, displayObj, "list",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let displays = DisplayModule.listDisplays()
            return JSBridge.newArray(ctx, displays.map { $0 as Any })
        }, "list", 0))

        JS_SetPropertyStr(ctx, displayObj, "getBrightness",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let id = argc > 0 && argv != nil
                ? CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, argv![0]))
                : CGMainDisplayID()
            return JSBridge.newFloat64(ctx, Double(DisplayModule.getBrightness(id)))
        }, "getBrightness", 1))

        JS_SetPropertyStr(ctx, displayObj, "setBrightness",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc > 0 else { return JSBridge.newBool(ctx!, false) }
            let level = Float(min(1, max(0, JSBridge.toDouble(ctx, argv[0]))))
            let id = argc > 1
                ? CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, argv[1]))
                : CGMainDisplayID()
            return JSBridge.newBool(ctx, DisplayModule.setBrightness(level, id))
        }, "setBrightness", 2))

        JS_SetPropertyStr(ctx, displayObj, "setXDREnabled",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc > 0, let module = displayModule(ctx) else {
                return JSBridge.newBool(ctx!, false)
            }
            return JSBridge.newBool(ctx, module.setXDREnabled(JSBridge.toBool(ctx, argv[0])))
        }, "setXDREnabled", 1))

        JS_SetPropertyStr(ctx, displayObj, "isXDREnabled",
                          JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = displayModule(ctx) else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, module.xdrWindow != nil)
        }, "isXDREnabled", 0))

        JS_SetPropertyStr(ctx, macotronObj, "display", displayObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        xdrWindow?.close()
        xdrWindow = nil
    }

    private static let brightnessFunctions: (GetBrightness?, SetBrightness?) = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ) else { return (nil, nil) }
        let get = dlsym(handle, "DisplayServicesGetBrightness")
            .map { unsafeBitCast($0, to: GetBrightness.self) }
        let set = dlsym(handle, "DisplayServicesSetBrightness")
            .map { unsafeBitCast($0, to: SetBrightness.self) }
        return (get, set)
    }()

    private static func getBrightness(_ id: CGDirectDisplayID) -> Float {
        guard let get = brightnessFunctions.0 else { return -1 }
        var level: Float = 0
        return get(id, &level) == 0 ? level : -1
    }

    private static func setBrightness(_ level: Float, _ id: CGDirectDisplayID) -> Bool {
        brightnessFunctions.1?(id, level) == 0
    }

    private func setXDREnabled(_ enabled: Bool) -> Bool {
        if !enabled {
            cleanup()
            return true
        }
        guard xdrWindow == nil else { return true }
        guard let screen = NSScreen.main,
              screen.maximumExtendedDynamicRangeColorComponentValue > 1 else { return false }

        // ponytail: this requests EDR headroom but cannot force unsupported display hardware.
        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer = CAMetalLayer()
        view.layer?.wantsExtendedDynamicRangeContent = true
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.orderFrontRegardless()
        xdrWindow = window
        return true
    }

    // MARK: - Display Enumeration

    private static func listDisplays() -> [[String: Any]] {
        var displays: [[String: Any]] = []
        let mainScreen = NSScreen.main

        for screen in NSScreen.screens {
            let frame = screen.frame
            let deviceDescription = screen.deviceDescription
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

            let isMain = (mainScreen != nil && screen == mainScreen)

            displays.append([
                "id": Int(screenNumber),
                "width": Int(frame.width),
                "height": Int(frame.height),
                "main": isMain
            ])
        }

        return displays
    }
}

@MainActor
private func displayModule(_ ctx: OpaquePointer) -> DisplayModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__displayModule"] as? DisplayModule
}
