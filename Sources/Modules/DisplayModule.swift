// DisplayModule.swift — macotron.display: enumerate connected displays
import AppKit
import CQuickJS
import CoreGraphics
import Darwin
import Foundation
import MacotronEngine
import QuartzCore

private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

private final class DisplayChangeState: @unchecked Sendable {
    static let shared = DisplayChangeState()
    weak var engine: Engine?
    var registered = false
}

private let displayReconfigCallback: CGDisplayReconfigurationCallBack = { display, flags, _ in
    DisplayChange.handle(display, flags)
}

enum DisplayChange {
    static func names(_ flags: CGDisplayChangeSummaryFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.addFlag) { names.append("add") }
        if flags.contains(.removeFlag) { names.append("remove") }
        if flags.contains(.movedFlag) { names.append("move") }
        if flags.contains(.setMainFlag) { names.append("main") }
        if flags.contains(.setModeFlag) { names.append("mode") }
        if flags.contains(.enabledFlag) { names.append("enable") }
        if flags.contains(.disabledFlag) { names.append("disable") }
        if flags.contains(.mirrorFlag) { names.append("mirror") }
        if flags.contains(.unMirrorFlag) { names.append("unmirror") }
        if flags.contains(.desktopShapeChangedFlag) { names.append("shape") }
        return names
    }

    static func shouldEmit(_ flags: CGDisplayChangeSummaryFlags) -> Bool {
        !names(flags).isEmpty
    }

    static func handle(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
        guard shouldEmit(flags) else { return }
        let id = Int(display)
        let flagNames = names(flags)
        Task { @MainActor in
            guard let engine = DisplayChangeState.shared.engine, let ctx = engine.context else { return }
            let data = JSBridge.newObject(ctx, ["id": id, "flags": flagNames as [Any]])
            engine.eventBus.emit("display:changed", engine: engine, data: data)
            JS_FreeValue(ctx, data)
        }
    }

    @MainActor
    static func start(_ engine: Engine) {
        DisplayChangeState.shared.engine = engine
        guard !DisplayChangeState.shared.registered else { return }
        CGDisplayRegisterReconfigurationCallback(displayReconfigCallback, nil)
        DisplayChangeState.shared.registered = true
    }

    @MainActor
    static func stop() {
        DisplayChangeState.shared.engine = nil
        guard DisplayChangeState.shared.registered else { return }
        CGDisplayRemoveReconfigurationCallback(displayReconfigCallback, nil)
        DisplayChangeState.shared.registered = false
    }
}

@MainActor
public final class DisplayModule: NativeModule {
    public let name = "display"
    public let moduleVersion = 3

    private var xdrWindow: NSWindow?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__displayModule"] = self
        if !engine.dryRun { DisplayChange.start(engine) }
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let displayObj = JS_NewObject(ctx)

        // macotron.display.list() -> id, frame, scale, rotation, builtin, mirrored, serial, mm
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

        JS_SetPropertyStr(ctx, displayObj, "setGamma",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc > 0, let white = DisplayGamma.rgb(ctx, argv[0]) else {
                return JSBridge.newBool(ctx!, false)
            }
            var black = DisplayGamma.RGB.black
            var id: CGDirectDisplayID?
            if argc > 1 {
                if JS_IsObject(argv[1]) {
                    black = DisplayGamma.rgb(ctx, argv[1]) ?? .black
                    if argc > 2 { id = CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, argv[2])) }
                } else {
                    id = CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, argv[1]))
                }
            }
            if DisplayModule.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            return JSBridge.newBool(ctx, DisplayGamma.set(white: white, black: black, id: id))
        }, "setGamma", 3))

        JS_SetPropertyStr(ctx, displayObj, "getGamma",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let id = argc > 0 && argv != nil
                ? CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, argv![0]))
                : CGMainDisplayID()
            let pair = DisplayGamma.get(id)
            return JSBridge.newObject(ctx, [
                "white": pair.white.js,
                "black": pair.black.js,
            ])
        }, "getGamma", 1))

        JS_SetPropertyStr(ctx, displayObj, "restoreGamma",
                          JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if DisplayModule.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            CGDisplayRestoreColorSyncSettings()
            return JSBridge.newBool(ctx, true)
        }, "restoreGamma", 0))

        JS_SetPropertyStr(ctx, macotronObj, "display", displayObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        xdrWindow?.close()
        xdrWindow = nil
        DisplayChange.stop()
        CGDisplayRestoreColorSyncSettings()
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

            let visible = screen.visibleFrame
            let mm = CGDisplayScreenSize(screenNumber)
            displays.append([
                "id": Int(screenNumber),
                "width": Int(frame.width),
                "height": Int(frame.height),
                "main": isMain,
                "frame": [
                    "x": Double(frame.origin.x),
                    "y": Double(frame.origin.y),
                    "width": Double(frame.width),
                    "height": Double(frame.height),
                ],
                "visibleFrame": [
                    "x": Double(visible.origin.x),
                    "y": Double(visible.origin.y),
                    "width": Double(visible.width),
                    "height": Double(visible.height),
                ],
                "scale": Double(screen.backingScaleFactor),
                "rotation": CGDisplayRotation(screenNumber),
                "builtin": CGDisplayIsBuiltin(screenNumber) != 0,
                "mirrored": CGDisplayIsInMirrorSet(screenNumber) != 0,
                "serial": Int(CGDisplaySerialNumber(screenNumber)),
                "mm": ["width": Double(mm.width), "height": Double(mm.height)],
            ])
        }

        return displays
    }

    private static func isDryRun(_ ctx: OpaquePointer) -> Bool {
        guard let opaque = JS_GetContextOpaque(ctx) else { return false }
        return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
    }
}

enum DisplayGamma {
    struct RGB: Equatable {
        var red: Float
        var green: Float
        var blue: Float

        static let black = RGB(red: 0, green: 0, blue: 0)
        static let white = RGB(red: 1, green: 1, blue: 1)

        var js: [String: Any] {
            ["red": Double(red), "green": Double(green), "blue": Double(blue)]
        }

        func clamped() -> RGB {
            RGB(
                red: min(1, max(0, red)),
                green: min(1, max(0, green)),
                blue: min(1, max(0, blue))
            )
        }
    }

    static let samples = 256

    static func tables(black: RGB, white: RGB) -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue]) {
        let lo = black.clamped()
        let hi = white.clamped()
        var r = [CGGammaValue](repeating: 0, count: samples)
        var g = [CGGammaValue](repeating: 0, count: samples)
        var b = [CGGammaValue](repeating: 0, count: samples)
        for i in 0..<samples {
            let t = Float(i) / Float(samples - 1)
            r[i] = lo.red + (hi.red - lo.red) * t
            g[i] = lo.green + (hi.green - lo.green) * t
            b[i] = lo.blue + (hi.blue - lo.blue) * t
        }
        return (r, g, b)
    }

    @MainActor
    static func rgb(_ ctx: OpaquePointer, _ value: JSValue) -> RGB? {
        guard !JSBridge.isUndefined(value) else { return nil }
        func chan(_ name: String) -> Float {
            let v = JSBridge.getProperty(ctx, value, name)
            defer { JS_FreeValue(ctx, v) }
            return JSBridge.isUndefined(v) ? 0 : Float(JSBridge.toDouble(ctx, v))
        }
        return RGB(red: chan("red"), green: chan("green"), blue: chan("blue")).clamped()
    }

    static func set(white: RGB, black: RGB, id: CGDirectDisplayID?) -> Bool {
        let t = tables(black: black, white: white)
        let targets: [CGDirectDisplayID]
        if let id {
            targets = [id]
        } else {
            var count: UInt32 = 16
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            guard CGGetActiveDisplayList(16, &ids, &count) == .success, count > 0 else { return false }
            targets = Array(ids.prefix(Int(count)))
        }
        var ok = true
        for display in targets {
            let err = t.r.withUnsafeBufferPointer { r in
                t.g.withUnsafeBufferPointer { g in
                    t.b.withUnsafeBufferPointer { b in
                        CGSetDisplayTransferByTable(
                            display,
                            UInt32(samples),
                            r.baseAddress,
                            g.baseAddress,
                            b.baseAddress
                        )
                    }
                }
            }
            if err != .success { ok = false }
        }
        return ok
    }

    static func get(_ id: CGDirectDisplayID) -> (white: RGB, black: RGB) {
        var r = [CGGammaValue](repeating: 0, count: samples)
        var g = [CGGammaValue](repeating: 0, count: samples)
        var b = [CGGammaValue](repeating: 0, count: samples)
        var count: UInt32 = 0
        let err = CGGetDisplayTransferByTable(id, UInt32(samples), &r, &g, &b, &count)
        guard err == .success, count > 0 else { return (.white, .black) }
        let last = Int(count) - 1
        return (
            white: RGB(red: r[last], green: g[last], blue: b[last]),
            black: RGB(red: r[0], green: g[0], blue: b[0])
        )
    }
}

@MainActor
private func displayModule(_ ctx: OpaquePointer) -> DisplayModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__displayModule"] as? DisplayModule
}
