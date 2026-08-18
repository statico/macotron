// WindowModule.swift — macotron.window: query and manipulate windows via AXUIElement
import AppKit
import CQuickJS
import MacotronEngine
import ApplicationServices
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "window")
private let snapEdgeThreshold: CGFloat = 20

/// Global state for the snap CGEvent tap callback (C function pointer cannot capture).
private final class WindowSnapState: @unchecked Sendable {
    weak var module: WindowModule?
    var eventTap: CFMachPort?
    static let shared = WindowSnapState()
}

@MainActor
public final class WindowModule: NativeModule {
    public let name = "window"

    private weak var engine: Engine?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var snapEnabled = false

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

        JS_SetPropertyStr(ctx, macotron, "window", windowObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        teardownSnapTap()
        snapEnabled = false
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
        let winDict: [String: Any] = [
            "id": Int(id),
            "title": windowTitle(win),
            "app": app,
            "frame": frameDict
        ]
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

    /// moveToFraction(id, {x?, y?, w?, h?}) -> bool
    /// Fractions are relative to the main screen frame.
    private static func jsMoveToFraction(_ ctx: OpaquePointer, windowID: Int32, opts: JSValue) -> JSValue {
        guard let win = resolveWindow(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }

        guard let screen = NSScreen.main else {
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

        let ok = applyFraction(win, x: fx, y: fy, w: fw, h: fh, screen: screen)
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

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = WindowSnapState.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            guard type == .leftMouseUp else { return Unmanaged.passRetained(event) }
            DispatchQueue.main.async {
                WindowSnapState.shared.module?.snapFocusedWindow(at: NSEvent.mouseLocation)
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
    }

    /// ponytail: any leftMouseUp near an edge snaps; upgrade to drag-session tracking if false positives matter
    private func snapFocusedWindow(at point: CGPoint) {
        guard snapEnabled else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let f = screen.frame
        let t = snapEdgeThreshold
        let left = point.x <= f.minX + t
        let right = point.x >= f.maxX - t
        let top = point.y >= f.maxY - t
        let bottom = point.y <= f.minY + t
        guard left || right || top || bottom else { return }

        let fx: CGFloat
        let fy: CGFloat
        let fw: CGFloat
        let fh: CGFloat

        if (left || right) && (top || bottom) {
            fx = right ? 0.5 : 0
            fy = bottom ? 0.5 : 0
            fw = 0.5
            fh = 0.5
        } else if left {
            fx = 0; fy = 0; fw = 0.5; fh = 1
        } else if right {
            fx = 0.5; fy = 0; fw = 0.5; fh = 1
        } else if top {
            fx = 0; fy = 0; fw = 1; fh = 1
        } else {
            return
        }

        guard let win = Self.focusedAXWindow() else { return }
        _ = Self.applyFraction(win, x: fx, y: fy, w: fw, h: fh, screen: screen)
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

    /// Apply fractional frame relative to screen.visibleFrame (same math as moveToFraction).
    private static func applyFraction(
        _ win: AXUIElement,
        x: CGFloat?,
        y: CGFloat?,
        w: CGFloat?,
        h: CGFloat?,
        screen: NSScreen
    ) -> Bool {
        let screenFrame = screen.visibleFrame
        let currentFrame = windowFrame(win)
        var origin = currentFrame.origin
        var size = currentFrame.size
        if let x { origin.x = screenFrame.origin.x + x * screenFrame.width }
        if let y { origin.y = screenFrame.origin.y + y * screenFrame.height }
        if let w { size.width = w * screenFrame.width }
        if let h { size.height = h * screenFrame.height }
        let posOk = setWindowPosition(win, point: origin)
        let sizeOk = setWindowSize(win, size: size)
        return posOk || sizeOk
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
