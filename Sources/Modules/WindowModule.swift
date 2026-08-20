// WindowModule.swift — macotron.window: query and manipulate windows via AXUIElement
import AppKit
import CQuickJS
import MacotronEngine
import ApplicationServices
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "window")

enum WindowMutation {
    static func perform(
        enhancedUI: Bool?,
        setEnhancedUI: (Bool) -> Void,
        mutate: () -> Bool
    ) -> Bool {
        if enhancedUI == true { setEnhancedUI(false) }
        defer {
            if enhancedUI == true { setEnhancedUI(true) }
        }
        return mutate()
    }

    static func applyFrame(setSize: () -> Bool, setPosition: () -> Bool) -> Bool {
        let firstSize = setSize()
        let position = setPosition()
        let finalSize = setSize()
        return firstSize || position || finalSize
    }
}

private struct SnapZone {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
}

private let defaultSnapZones: [String: SnapZone] = [
    "left": SnapZone(x: 0, y: 0, w: 0.5, h: 1),
    "right": SnapZone(x: 0.5, y: 0, w: 0.5, h: 1),
    "top": SnapZone(x: 0, y: 0, w: 1, h: 1),
    "bottom": SnapZone(x: 0, y: 0.5, w: 1, h: 0.5),
    "tl": SnapZone(x: 0, y: 0, w: 0.5, h: 0.5),
    "tr": SnapZone(x: 0.5, y: 0, w: 0.5, h: 0.5),
    "bl": SnapZone(x: 0, y: 0.5, w: 0.5, h: 0.5),
    "br": SnapZone(x: 0.5, y: 0.5, w: 0.5, h: 0.5),
]

private let snapSlotAliases: [String: String] = [
    "left": "left", "right": "right", "top": "top", "bottom": "bottom",
    "tl": "tl", "tr": "tr", "bl": "bl", "br": "br",
    "top-left": "tl", "topleft": "tl", "nw": "tl",
    "top-right": "tr", "topright": "tr", "ne": "tr",
    "bottom-left": "bl", "bottomleft": "bl", "sw": "bl",
    "bottom-right": "br", "bottomright": "br", "se": "br",
    "maximize": "top", "full": "top",
]

struct SnapDrag {
    var start: CGPoint?
    var dragging = false
    static let slop: CGFloat = 8

    mutating func down(_ p: CGPoint) {
        start = p
        dragging = false
    }

    mutating func moved(_ p: CGPoint) {
        guard let start else { return }
        if hypot(p.x - start.x, p.y - start.y) > Self.slop { dragging = true }
    }

    mutating func up() -> Bool {
        let ok = dragging
        start = nil
        dragging = false
        return ok
    }
}

/// Global state for the snap CGEvent tap callback (C function pointer cannot capture).
private final class WindowSnapState: @unchecked Sendable {
    weak var module: WindowModule?
    var eventTap: CFMachPort?
    var drag = SnapDrag()
    static let shared = WindowSnapState()
}

@MainActor
public final class WindowModule: NativeModule {
    public let name = "window"
    public let moduleVersion = 3

    private weak var engine: Engine?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var snapEnabled = false
    private var snapThreshold: CGFloat = 20
    private var snapCorner: CGFloat = 48
    private var snapGap: CGFloat = 0
    private var snapZones: [String: SnapZone] = defaultSnapZones

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        WindowSnapState.shared.module = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let windowObj = JS_NewObject(ctx)

        // ---------- getAll() ----------
        JS_SetPropertyStr(ctx, windowObj, "getAll", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return WindowModule.jsGetAll(ctx)
        }, "getAll", 0))

        // ---------- focused() ----------
        JS_SetPropertyStr(ctx, windowObj, "focused", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return WindowModule.jsFocused(ctx)
        }, "focused", 0))

        // ---------- focus(id) ----------
        JS_SetPropertyStr(ctx, windowObj, "focus", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            return WindowModule.jsFocus(ctx, windowID: JSBridge.toInt32(ctx, argv[0]))
        }, "focus", 1))

        // ---------- move(id, {x?, y?, width?, height?}) ----------
        JS_SetPropertyStr(ctx, windowObj, "move", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            let windowID = JSBridge.toInt32(ctx, argv[0])
            let opts = argv[1]
            return WindowModule.jsMove(ctx, windowID: windowID, opts: opts)
        }, "move", 2))

        // ---------- moveToFraction(id, {x?, y?, w?, h?}) ----------
        JS_SetPropertyStr(ctx, windowObj, "moveToFraction", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            let windowID = JSBridge.toInt32(ctx, argv[0])
            let opts = argv[1]
            return WindowModule.jsMoveToFraction(ctx, windowID: windowID, opts: opts)
        }, "moveToFraction", 2))

        // ---------- setSnapEnabled(enabled) ----------
        JS_SetPropertyStr(ctx, windowObj, "setSnapEnabled", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            let enabled = JSBridge.toBool(ctx, argv[0])
            let ok = WindowSnapState.shared.module?.setSnapEnabled(enabled) ?? false
            return QJS_NewBool(ctx, ok ? 1 : 0)
        }, "setSnapEnabled", 1))

        // ---------- isSnapEnabled() ----------
        JS_SetPropertyStr(ctx, windowObj, "isSnapEnabled", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_NewBool(ctx!, 0) }
            let on = WindowSnapState.shared.module?.snapEnabled ?? false
            return QJS_NewBool(ctx, on ? 1 : 0)
        }, "isSnapEnabled", 0))

        JS_SetPropertyStr(ctx, windowObj, "snap", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            let ok = WindowSnapState.shared.module?.configureSnap(ctx, argv[0]) ?? false
            return QJS_NewBool(ctx, ok ? 1 : 0)
        }, "snap", 1))

        JS_SetPropertyStr(ctx, windowObj, "minimize", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            let on = argc < 2 || JSBridge.toBool(ctx, argv[1])
            return QJS_NewBool(ctx, WindowAX.minimize(JSBridge.toInt32(ctx, argv[0]), on) ? 1 : 0)
        }, "minimize", 2))

        JS_SetPropertyStr(ctx, windowObj, "close", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            return QJS_NewBool(ctx, WindowAX.close(JSBridge.toInt32(ctx, argv[0])) ? 1 : 0)
        }, "close", 1))

        JS_SetPropertyStr(ctx, windowObj, "setFullscreen", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            return QJS_NewBool(
                ctx,
                WindowAX.setFullscreen(JSBridge.toInt32(ctx, argv[0]), JSBridge.toBool(ctx, argv[1])) ? 1 : 0
            )
        }, "setFullscreen", 2))

        JS_SetPropertyStr(ctx, macotron, "window", windowObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        WindowWatch.start(engine)
    }

    public func cleanup() {
        WindowWatch.stop()
        teardownSnapTap()
        snapEnabled = false
        snapZones = defaultSnapZones
        snapThreshold = 20
        snapCorner = 48
        snapGap = 0
        WindowSnapState.shared.module = nil
        WindowSnapState.shared.eventTap = nil
    }

    // MARK: - AX Helpers

    /// Collect all on-screen windows across all applications.
    private static func allWindows() -> [(pid: pid_t, app: String, axWindow: AXUIElement)] {
        var results: [(pid_t, String, AXUIElement)] = []

        // Walk running apps that own windows
        let workspace = NSWorkspace.shared
        for runApp in workspace.runningApplications {
            guard runApp.activationPolicy == .regular else { continue }
            let pid = runApp.processIdentifier
            let appName = runApp.localizedName ?? "Unknown"
            let appRef = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for win in windows {
                results.append((pid, appName, win))
            }
        }
        return results
    }

    /// Extract title from an AXUIElement window.
    private static func windowTitle(_ win: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
        if err == .success, let title = titleRef as? String {
            return title
        }
        return ""
    }

    /// Extract frame (position + size) from an AXUIElement window.
    private static func windowFrame(_ win: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var origin = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
           let posRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    /// Build a stable integer ID from a window's AXUIElement.
    /// We hash the pid + window index to produce a consistent numeric handle
    /// that JS can pass back for move operations.
    private static func windowID(pid: pid_t, index: Int) -> Int32 {
        // Combine pid and index into a simple integer handle
        return Int32(pid) * 1000 + Int32(index)
    }

    /// Resolve a numeric window ID back to its AXUIElement.
    private static func resolveWindow(id: Int32) -> AXUIElement? {
        let pid = pid_t(id / 1000)
        let index = Int(id % 1000)
        let appRef = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return nil }
        guard index >= 0, index < windows.count else { return nil }
        return windows[index]
    }

    /// Build a JS object {id, title, app, frame:{x,y,width,height}} for a window.
    private static func windowToJS(
        _ ctx: OpaquePointer,
        pid: pid_t,
        index: Int,
        app: String,
        win: AXUIElement
    ) -> JSValue {
        let frame = windowFrame(win)
        let id = windowID(pid: pid, index: index)

        let frameDict: [String: Any] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height)
        ]
        var winDict: [String: Any] = [
            "id": Int(id),
            "title": windowTitle(win),
            "app": app,
            "frame": frameDict
        ]
        if let displayID = screen(forAXFrame: frame).map(Self.displayID) {
            winDict["display"] = Int(displayID)
        }
        return JSBridge.newObject(ctx, winDict)
    }

    // MARK: - JS Implementations

    /// getAll() -> JS array of window objects
    private static func jsGetAll(_ ctx: OpaquePointer) -> JSValue {
        let jsArr = JS_NewArray(ctx)
        var arrIdx: UInt32 = 0

        // Group windows by app to get per-app indices
        let workspace = NSWorkspace.shared
        for runApp in workspace.runningApplications {
            guard runApp.activationPolicy == .regular else { continue }
            let pid = runApp.processIdentifier
            let appName = runApp.localizedName ?? "Unknown"
            let appRef = AXUIElementCreateApplication(pid)

            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for (i, win) in windows.enumerated() {
                let jsWin = windowToJS(ctx, pid: pid, index: i, app: appName, win: win)
                JS_SetPropertyUint32(ctx, jsArr, arrIdx, jsWin)
                arrIdx += 1
            }
        }

        return jsArr
    }

    /// focused() -> window object or QJS_Null()
    private static func jsFocused(_ ctx: OpaquePointer) -> JSValue {
        let sysWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedAppRef: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(
            sysWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appErr == .success, let focusedApp = focusedAppRef else {
            return QJS_Null()
        }

        // Get the focused window of that application
        var focusedWinRef: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWinRef
        )
        guard winErr == .success, let focusedWin = focusedWinRef else {
            return QJS_Null()
        }

        let axWin = focusedWin as! AXUIElement

        // Get the PID of the focused application
        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)

        // Figure out the index of this window among the app's windows
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        var windowIndex = 0
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for (i, win) in windows.enumerated() {
                // Compare by checking title + position as a heuristic
                if windowTitle(win) == windowTitle(axWin) {
                    let f1 = windowFrame(win)
                    let f2 = windowFrame(axWin)
                    if f1 == f2 {
                        windowIndex = i
                        break
                    }
                }
            }
        }

        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown"
        return windowToJS(ctx, pid: pid, index: windowIndex, app: appName, win: axWin)
    }

    /// focus(id) -> bool — raise, unminimize, activate the owning app
    private static func jsFocus(_ ctx: OpaquePointer, windowID: Int32) -> JSValue {
        guard let win = resolveWindow(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }
        AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let pid = pid_t(windowID / 1000)
        _ = NSRunningApplication(processIdentifier: pid)?.activate()
        return QJS_NewBool(ctx, 1)
    }

    /// move(id, {x?, y?, width?, height?}) -> bool
    private static func jsMove(_ ctx: OpaquePointer, windowID: Int32, opts: JSValue) -> JSValue {
        guard let win = resolveWindow(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }

        let currentFrame = windowFrame(win)
        var newOrigin = currentFrame.origin
        var newSize = currentFrame.size

        // Read optional properties from opts object
        let xVal = JSBridge.getProperty(ctx, opts, "x")
        let yVal = JSBridge.getProperty(ctx, opts, "y")
        let wVal = JSBridge.getProperty(ctx, opts, "width")
        let hVal = JSBridge.getProperty(ctx, opts, "height")

        if !JSBridge.isUndefined(xVal) { newOrigin.x = CGFloat(JSBridge.toDouble(ctx, xVal)) }
        if !JSBridge.isUndefined(yVal) { newOrigin.y = CGFloat(JSBridge.toDouble(ctx, yVal)) }
        if !JSBridge.isUndefined(wVal) { newSize.width = CGFloat(JSBridge.toDouble(ctx, wVal)) }
        if !JSBridge.isUndefined(hVal) { newSize.height = CGFloat(JSBridge.toDouble(ctx, hVal)) }

        JS_FreeValue(ctx, xVal)
        JS_FreeValue(ctx, yVal)
        JS_FreeValue(ctx, wVal)
        JS_FreeValue(ctx, hVal)

        let posOk = setWindowPosition(win, point: newOrigin)
        let sizeOk = setWindowSize(win, size: newSize)

        return QJS_NewBool(ctx, (posOk || sizeOk) ? 1 : 0)
    }

    /// moveToFraction(id, {x?, y?, w?, h?, display?}) -> bool
    /// Fractions are relative to the window's current display, or `display` from macotron.display.list().
    private static func jsMoveToFraction(_ ctx: OpaquePointer, windowID: Int32, opts: JSValue) -> JSValue {
        guard let win = resolveWindow(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }

        var screen = Self.screen(forAXFrame: windowFrame(win)) ?? NSScreen.screens.first
        let displayVal = JSBridge.getProperty(ctx, opts, "display")
        if !JSBridge.isUndefined(displayVal), !JSBridge.isNull(displayVal) {
            let id = CGDirectDisplayID(bitPattern: JSBridge.toInt32(ctx, displayVal))
            if let match = Self.screen(displayID: id) {
                screen = match
            }
        }
        JS_FreeValue(ctx, displayVal)
        guard let screen else {
            return QJS_NewBool(ctx, 0)
        }

        let xVal = JSBridge.getProperty(ctx, opts, "x")
        let yVal = JSBridge.getProperty(ctx, opts, "y")
        let wVal = JSBridge.getProperty(ctx, opts, "w")
        let hVal = JSBridge.getProperty(ctx, opts, "h")

        var fx: CGFloat?
        var fy: CGFloat?
        var fw: CGFloat?
        var fh: CGFloat?

        if !JSBridge.isUndefined(xVal) { fx = CGFloat(JSBridge.toDouble(ctx, xVal)) }
        if !JSBridge.isUndefined(yVal) { fy = CGFloat(JSBridge.toDouble(ctx, yVal)) }
        if !JSBridge.isUndefined(wVal) { fw = CGFloat(JSBridge.toDouble(ctx, wVal)) }
        if !JSBridge.isUndefined(hVal) { fh = CGFloat(JSBridge.toDouble(ctx, hVal)) }

        JS_FreeValue(ctx, xVal)
        JS_FreeValue(ctx, yVal)
        JS_FreeValue(ctx, wVal)
        JS_FreeValue(ctx, hVal)

        let ok = applyFraction(win, x: fx, y: fy, w: fw, h: fh, screen: screen, gap: 0)
        return QJS_NewBool(ctx, ok ? 1 : 0)
    }

    // MARK: - Snap

    @discardableResult
    func setSnapEnabled(_ enabled: Bool) -> Bool {
        if engine?.dryRun == true {
            snapEnabled = enabled
            return true
        }
        if enabled {
            guard setupSnapTap() else {
                snapEnabled = false
                return false
            }
            snapEnabled = true
            return true
        }
        teardownSnapTap()
        snapEnabled = false
        return true
    }

    private func setupSnapTap() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = WindowSnapState.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            let point = NSEvent.mouseLocation
            switch type {
            case .leftMouseDown:
                WindowSnapState.shared.drag.down(point)
            case .leftMouseDragged:
                WindowSnapState.shared.drag.moved(point)
            case .leftMouseUp:
                if WindowSnapState.shared.drag.up() {
                    DispatchQueue.main.async {
                        WindowSnapState.shared.module?.snapFocusedWindow(at: NSEvent.mouseLocation)
                    }
                }
            default:
                break
            }
            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        guard let eventTap else {
            logger.error("Failed to create window snap CGEvent tap")
            return false
        }

        WindowSnapState.shared.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.info("Window snap event tap installed")
        return true
    }

    private func teardownSnapTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        WindowSnapState.shared.eventTap = nil
        WindowSnapState.shared.drag = SnapDrag()
    }

    private func snapFocusedWindow(at point: CGPoint) {
        guard snapEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        guard let slot = snapSlot(at: point, screen: screen), let zone = snapZones[slot] else { return }
        guard let win = Self.focusedAXWindow() else { return }
        _ = Self.applyFraction(win, x: zone.x, y: zone.y, w: zone.w, h: zone.h, screen: screen, gap: snapGap)
    }

    private func snapSlot(at point: CGPoint, screen: NSScreen) -> String? {
        let f = screen.frame
        let c = snapCorner
        let t = snapThreshold
        let leftC = point.x <= f.minX + c
        let rightC = point.x >= f.maxX - c
        let bottomC = point.y <= f.minY + c
        let topC = point.y >= f.maxY - c
        if leftC && topC { return "tl" }
        if rightC && topC { return "tr" }
        if leftC && bottomC { return "bl" }
        if rightC && bottomC { return "br" }
        if point.x <= f.minX + t { return "left" }
        if point.x >= f.maxX - t { return "right" }
        if point.y >= f.maxY - t { return "top" }
        if point.y <= f.minY + t { return "bottom" }
        return nil
    }

    func configureSnap(_ ctx: OpaquePointer, _ opts: JSValue) -> Bool {
        if JS_IsBool(opts) {
            return setSnapEnabled(JSBridge.toBool(ctx, opts))
        }
        let enabledVal = JSBridge.getProperty(ctx, opts, "enabled")
        let enabled = JSBridge.isUndefined(enabledVal) || JSBridge.isNull(enabledVal)
            ? true : JSBridge.toBool(ctx, enabledVal)
        JS_FreeValue(ctx, enabledVal)

        let thresholdVal = JSBridge.getProperty(ctx, opts, "threshold")
        if !JSBridge.isUndefined(thresholdVal), !JSBridge.isNull(thresholdVal) {
            snapThreshold = max(1, CGFloat(JSBridge.toDouble(ctx, thresholdVal)))
        }
        JS_FreeValue(ctx, thresholdVal)

        let cornerVal = JSBridge.getProperty(ctx, opts, "corner")
        if !JSBridge.isUndefined(cornerVal), !JSBridge.isNull(cornerVal) {
            snapCorner = max(1, CGFloat(JSBridge.toDouble(ctx, cornerVal)))
        }
        JS_FreeValue(ctx, cornerVal)

        let gapVal = JSBridge.getProperty(ctx, opts, "gap")
        if !JSBridge.isUndefined(gapVal), !JSBridge.isNull(gapVal) {
            snapGap = max(0, CGFloat(JSBridge.toDouble(ctx, gapVal)))
        }
        JS_FreeValue(ctx, gapVal)

        let zonesVal = JSBridge.getProperty(ctx, opts, "zones")
        if JS_IsObject(zonesVal), !JSBridge.isUndefined(zonesVal), !JSBridge.isNull(zonesVal), !JS_IsArray(zonesVal) {
            snapZones = Self.parseSnapZones(ctx, zonesVal)
        }
        JS_FreeValue(ctx, zonesVal)

        return setSnapEnabled(enabled)
    }

    private static func parseSnapZones(_ ctx: OpaquePointer, _ val: JSValue) -> [String: SnapZone] {
        guard let dict = JSBridge.jsToSwift(ctx, val) as? [String: Any] else { return [:] }
        var out: [String: SnapZone] = [:]
        for (rawKey, raw) in dict {
            let key = snapSlotAliases[rawKey.lowercased()] ?? rawKey.lowercased()
            guard let frame = raw as? [String: Any] else { continue }
            func num(_ k: String) -> CGFloat? {
                if let d = frame[k] as? Double { return CGFloat(d) }
                if let i = frame[k] as? Int { return CGFloat(i) }
                return nil
            }
            guard let x = num("x"), let y = num("y"), let w = num("w"), let h = num("h") else { continue }
            out[key] = SnapZone(x: x, y: y, w: w, h: h)
        }
        return out
    }

    private static func focusedAXWindow() -> AXUIElement? {
        let sysWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            sysWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        ) == .success, let focusedApp = focusedAppRef else { return nil }

        var focusedWinRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWinRef
        ) == .success, let focusedWin = focusedWinRef else { return nil }

        return (focusedWin as! AXUIElement)
    }

    // MARK: - AX Mutation Helpers

    /// Apply fractional frame relative to screen.visibleFrame in AX coordinates (y: 0 is the top).
    private static func applyFraction(
        _ win: AXUIElement,
        x: CGFloat?,
        y: CGFloat?,
        w: CGFloat?,
        h: CGFloat?,
        screen: NSScreen,
        gap: CGFloat = 0
    ) -> Bool {
        let vis = cocoaRectToAX(screen.visibleFrame)
        let g = gap
        let currentFrame = windowFrame(win)
        var origin = currentFrame.origin
        var size = currentFrame.size
        if let x { origin.x = vis.origin.x + x * vis.width + g }
        if let y { origin.y = vis.origin.y + y * vis.height + g }
        if let w { size.width = max(1, w * vis.width - 2 * g) }
        if let h { size.height = max(1, h * vis.height - 2 * g) }

        var pid: pid_t = 0
        let app = AXUIElementGetPid(win, &pid) == .success ? AXUIElementCreateApplication(pid) : nil
        var enhancedUIValue: CFTypeRef?
        let enhancedUI = app.flatMap {
            AXUIElementCopyAttributeValue($0, "AXEnhancedUserInterface" as CFString, &enhancedUIValue) == .success
                ? enhancedUIValue as? Bool
                : nil
        }

        return WindowMutation.perform(
            enhancedUI: enhancedUI,
            setEnhancedUI: {
                guard let app else { return }
                let error = AXUIElementSetAttributeValue(
                    app,
                    "AXEnhancedUserInterface" as CFString,
                    $0 ? kCFBooleanTrue : kCFBooleanFalse
                )
                if error != .success {
                    logger.error("Failed to set AXEnhancedUserInterface: \(error.rawValue)")
                }
            },
            mutate: {
                WindowMutation.applyFrame(
                    setSize: { setWindowSize(win, size: size) },
                    setPosition: { setWindowPosition(win, point: origin) }
                )
            }
        )
    }

    /// Screen whose Cocoa origin is (0,0) — AX/Quartz y is measured down from this screen's top.
    private static func axOriginScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    private static func axRectToCocoa(_ ax: CGRect) -> CGRect {
        guard let primary = axOriginScreen() else { return ax }
        let y = primary.frame.maxY - ax.origin.y - ax.size.height
        return CGRect(x: ax.origin.x, y: y, width: ax.size.width, height: ax.size.height)
    }

    private static func cocoaRectToAX(_ cocoa: CGRect) -> CGRect {
        guard let primary = axOriginScreen() else { return cocoa }
        let y = primary.frame.maxY - cocoa.origin.y - cocoa.size.height
        return CGRect(x: cocoa.origin.x, y: y, width: cocoa.size.width, height: cocoa.size.height)
    }

    private static func screen(forAXFrame ax: CGRect) -> NSScreen? {
        let cocoa = axRectToCocoa(ax)
        let center = CGPoint(x: cocoa.midX, y: cocoa.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return hit
        }
        return NSScreen.screens.max { a, b in
            area(a.frame.intersection(cocoa)) < area(b.frame.intersection(cocoa))
        }
    }

    private static func screen(displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            Self.displayID(of: $0) == displayID
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isInfinite ? 0 : rect.width * rect.height
    }

    private static func setWindowPosition(_ win: AXUIElement, point: CGPoint) -> Bool {
        var pt = point
        guard let value = AXValueCreate(.cgPoint, &pt) else { return false }
        let err = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, value)
        return err == .success
    }

    private static func setWindowSize(_ win: AXUIElement, size: CGSize) -> Bool {
        var sz = size
        guard let value = AXValueCreate(.cgSize, &sz) else { return false }
        let err = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, value)
        return err == .success
    }
}
