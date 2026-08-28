// WindowModule.swift — macotron.window: query and manipulate windows via AXUIElement
import AppKit
import CQuickJS
import MacotronEngine
import ApplicationServices
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "window")

struct SnapDrag {
    var start: CGPoint?
    var dragging = false
    /// Where the frontmost window sat when this drag began, and whether it has
    /// since moved. A drag that moves no window is not a window drag.
    var windowOrigin: CGPoint?
    var movedWindow = false
    var lastWindowCheck: Date?
    static let slop: CGFloat = 8

    mutating func down(_ p: CGPoint) {
        start = p
        dragging = false
        windowOrigin = nil
        movedWindow = false
        lastWindowCheck = nil
    }

    mutating func moved(_ p: CGPoint) {
        guard let start else { return }
        if hypot(p.x - start.x, p.y - start.y) > Self.slop { dragging = true }
    }

    /// Feed the frontmost window's origin during a drag. The first sample is the
    /// baseline; a later one past the slop means this really is a window drag.
    mutating func sample(windowOrigin origin: CGPoint) {
        guard let start = windowOrigin else {
            windowOrigin = origin
            return
        }
        if hypot(origin.x - start.x, origin.y - start.y) > Self.slop { movedWindow = true }
    }

    mutating func up() -> Bool {
        let ok = dragging && movedWindow
        start = nil
        dragging = false
        windowOrigin = nil
        movedWindow = false
        lastWindowCheck = nil
        return ok
    }
}

/// Global state for the snap CGEvent tap callback (C function pointer cannot capture).
/// The callback runs on the shared tap thread, so everything it touches is behind a lock;
/// `module` is the exception, reached only after a hop to main.
private final class WindowSnapState: @unchecked Sendable {
    weak var module: WindowModule?
    static let shared = WindowSnapState()

    private let lock = NSLock()
    private var _tap: CFMachPort?
    private var _drag = SnapDrag()
    private var _flags: CGEventFlags = []

    var tap: CFMachPort? {
        get { lock.lock(); defer { lock.unlock() }; return _tap }
        set { lock.lock(); _tap = newValue; lock.unlock() }
    }

    var flags: CGEventFlags {
        get { lock.lock(); defer { lock.unlock() }; return _flags }
        set { lock.lock(); _flags = newValue; lock.unlock() }
    }

    /// Keep the body short: the tap callback blocks on this lock for every drag event.
    func withDrag<T>(_ body: (inout SnapDrag) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&_drag)
    }
}

@MainActor
public final class WindowModule: NativeModule {
    public let name = "window"
    public let moduleVersion = 5

    private weak var engine: Engine?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var snapEnabled = false
    private var snapThreshold: CGFloat = 20
    private var snapCorner: CGFloat = 80
    private var snapGap: CGFloat = 0
    private var snapZones: [String: SnapZone] = SnapGeometry.defaultZones
    private var snapModifierSets: [(flags: CGEventFlags, zones: [String: SnapZone])] = []

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
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
            return WindowModule.jsFocus(ctx, windowID: JSBridge.toInt32(ctx, argv[0]))
        }, "focus", 1))

        // ---------- move(id, {x?, y?, width?, height?}) ----------
        JS_SetPropertyStr(ctx, windowObj, "move", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
            let windowID = JSBridge.toInt32(ctx, argv[0])
            let opts = argv[1]
            return WindowModule.jsMove(ctx, windowID: windowID, opts: opts)
        }, "move", 2))

        // ---------- moveToFraction(id, {x?, y?, w?, h?}) ----------
        JS_SetPropertyStr(ctx, windowObj, "moveToFraction", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
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

        JS_SetPropertyStr(ctx, windowObj, "previewFraction", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_NewBool(ctx!, 0) }
            if argc < 1 || argv == nil || JSBridge.isUndefined(argv![0]) || JSBridge.isNull(argv![0]) {
                SnapPreview.shared.hide()
                return QJS_NewBool(ctx, 1)
            }
            let ok = WindowSnapState.shared.module?.previewFraction(ctx, argv![0]) ?? false
            return QJS_NewBool(ctx, ok ? 1 : 0)
        }, "previewFraction", 1))

        JS_SetPropertyStr(ctx, windowObj, "minimize", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
            let on = argc < 2 || JSBridge.toBool(ctx, argv[1])
            return QJS_NewBool(ctx, WindowAX.minimize(JSBridge.toInt32(ctx, argv[0]), on) ? 1 : 0)
        }, "minimize", 2))

        JS_SetPropertyStr(ctx, windowObj, "close", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_NewBool(ctx!, 0) }
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
            return QJS_NewBool(ctx, WindowAX.close(JSBridge.toInt32(ctx, argv[0])) ? 1 : 0)
        }, "close", 1))

        JS_SetPropertyStr(ctx, windowObj, "setFullscreen", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else { return QJS_NewBool(ctx!, 0) }
            if Engine.isDryRun(ctx) { return QJS_NewBool(ctx, 1) }
            return QJS_NewBool(
                ctx,
                WindowAX.setFullscreen(JSBridge.toInt32(ctx, argv[0]), JSBridge.toBool(ctx, argv[1])) ? 1 : 0
            )
        }, "setFullscreen", 2))

        JS_SetPropertyStr(ctx, windowObj, "restore", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else {
                return JSBridge.newObject(ctx!, ["restored": 0, "missing": 0])
            }
            return WindowModule.jsRestore(ctx, entries: argv[0])
        }, "restore", 1))

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
        snapZones = SnapGeometry.defaultZones
        snapModifierSets = []
        snapThreshold = 20
        snapCorner = 80
        snapGap = 0
        WindowSnapState.shared.module = nil
        WindowSnapState.shared.tap = nil
        WindowSnapState.shared.flags = []
    }

    // MARK: - AX Helpers

    /// Build a JS object {id, title, app, frame:{x,y,width,height}} for a window.
    private static func windowToJS(
        _ ctx: OpaquePointer,
        pid: pid_t,
        index: Int,
        app: String,
        win: AXUIElement
    ) -> JSValue {
        let frame = WindowAX.frame(win)
        let id = WindowAX.windowID(pid: pid, index: index)

        var winDict: [String: Any] = [
            "id": Int(id),
            "title": WindowAX.title(win),
            "app": app,
            "frame": frame.js
        ]
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            winDict["bundleID"] = bundleID
        }
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

        WindowAX.enumerate { runApp, i, win in
            let jsWin = windowToJS(ctx, pid: runApp.processIdentifier, index: i,
                                   app: runApp.localizedName ?? "Unknown", win: win)
            JS_SetPropertyUint32(ctx, jsArr, arrIdx, jsWin)
            arrIdx += 1
        }

        return jsArr
    }

    /// focused() -> window object or QJS_Null()
    private static func jsFocused(_ ctx: OpaquePointer) -> JSValue {
        guard let axWin = focusedAXWindow() else { return QJS_Null() }
        let pid = pid(of: axWin)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "Unknown"
        return windowToJS(ctx, pid: pid, index: WindowAX.index(of: axWin, pid: pid), app: appName, win: axWin)
    }

    /// focus(id) -> bool — raise, unminimize, activate the owning app
    private static func jsFocus(_ ctx: OpaquePointer, windowID: Int32) -> JSValue {
        guard let win = WindowAX.resolve(id: windowID) else {
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
        guard let win = WindowAX.resolve(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }

        let currentFrame = WindowAX.frame(win)
        var newOrigin = currentFrame.origin
        var newSize = currentFrame.size

        if let x = JSBridge.double(ctx, opts, "x") { newOrigin.x = CGFloat(x) }
        if let y = JSBridge.double(ctx, opts, "y") { newOrigin.y = CGFloat(y) }
        if let w = JSBridge.double(ctx, opts, "width") { newSize.width = CGFloat(w) }
        if let h = JSBridge.double(ctx, opts, "height") { newSize.height = CGFloat(h) }

        let posOk = setWindowPosition(win, point: newOrigin)
        let sizeOk = setWindowSize(win, size: newSize)

        return QJS_NewBool(ctx, (posOk || sizeOk) ? 1 : 0)
    }

    /// moveToFraction(id, {x?, y?, w?, h?, display?}) -> bool
    /// Fractions are relative to the window's current display, or `display` from macotron.display.list().
    private static func jsMoveToFraction(_ ctx: OpaquePointer, windowID: Int32, opts: JSValue) -> JSValue {
        guard let win = WindowAX.resolve(id: windowID) else {
            return QJS_NewBool(ctx, 0)
        }

        var screen = Self.screen(forAXFrame: WindowAX.frame(win)) ?? NSScreen.screens.first
        if let display = JSBridge.int(ctx, opts, "display"),
           let match = Self.screen(displayID: CGDirectDisplayID(bitPattern: Int32(truncatingIfNeeded: display))) {
            screen = match
        }
        guard let screen else {
            return QJS_NewBool(ctx, 0)
        }

        let ok = applyFraction(
            win,
            x: JSBridge.double(ctx, opts, "x").map { CGFloat($0) },
            y: JSBridge.double(ctx, opts, "y").map { CGFloat($0) },
            w: JSBridge.double(ctx, opts, "w").map { CGFloat($0) },
            h: JSBridge.double(ctx, opts, "h").map { CGFloat($0) },
            screen: screen,
            gap: 0
        )
        return QJS_NewBool(ctx, ok ? 1 : 0)
    }

    /// restore([{app, bundleID?, title?, frame, display?}]) -> { restored, missing }
    private static func jsRestore(_ ctx: OpaquePointer, entries: JSValue) -> JSValue {
        let raw = JSBridge.jsToSwift(ctx, entries)
        let list = raw as? [Any] ?? []
        if Engine.isDryRun(ctx) {
            return JSBridge.newObject(ctx, ["restored": list.count, "missing": 0])
        }

        var remaining = snapshotWindows()
        var restored = 0
        var missing = 0
        for item in list {
            guard let dict = item as? [String: Any],
                  let app = dict["app"] as? String, !app.isEmpty else {
                missing += 1
                continue
            }
            let entry = WindowRestore.Entry(
                app: app,
                title: dict["title"] as? String,
                bundleID: dict["bundleID"] as? String
            )
            guard let id = WindowRestore.match(remaining, entry) else {
                missing += 1
                continue
            }
            remaining.removeAll { $0.id == id }
            let frame = dict["frame"] as? [String: Any] ?? [:]
            let frameObj = JSBridge.newObject(ctx, frame)
            let moved = jsMove(ctx, windowID: id, opts: frameObj)
            JS_FreeValue(ctx, frameObj)
            let ok = JSBridge.toBool(ctx, moved)
            JS_FreeValue(ctx, moved)
            if ok {
                restored += 1
            } else {
                missing += 1
            }
        }
        return JSBridge.newObject(ctx, ["restored": restored, "missing": missing])
    }

    private static func snapshotWindows() -> [WindowRestore.Window] {
        var results: [WindowRestore.Window] = []
        WindowAX.enumerate { runApp, i, win in
            results.append(WindowRestore.Window(
                id: WindowAX.windowID(pid: runApp.processIdentifier, index: i),
                app: runApp.localizedName ?? "Unknown",
                title: WindowAX.title(win),
                bundleID: runApp.bundleIdentifier
            ))
        }
        return results
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
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = WindowSnapState.shared.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            WindowSnapState.shared.flags = event.flags
            let point = NSEvent.mouseLocation
            switch type {
            case .leftMouseDown:
                WindowSnapState.shared.withDrag { $0.down(point) }
            case .leftMouseDragged:
                WindowSnapState.shared.withDrag { $0.moved(point) }
                DispatchQueue.main.async {
                    WindowSnapState.shared.module?.updateSnapPreview(at: point)
                }
            case .flagsChanged:
                DispatchQueue.main.async {
                    WindowSnapState.shared.module?.updateSnapPreview(at: point)
                }
            case .leftMouseUp:
                let dragging = WindowSnapState.shared.withDrag { $0.up() }
                DispatchQueue.main.async {
                    WindowSnapState.shared.module?.finishSnap(at: point, dragging: dragging)
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

        WindowSnapState.shared.tap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            EventTapThread.shared.add(runLoopSource)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func teardownSnapTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            EventTapThread.shared.remove(runLoopSource)
        }
        eventTap = nil
        runLoopSource = nil
        WindowSnapState.shared.tap = nil
        WindowSnapState.shared.withDrag { $0 = SnapDrag() }
        WindowSnapState.shared.flags = []
        SnapPreview.shared.hide()
    }

    private func currentZones() -> [String: SnapZone] {
        SnapGeometry.activeZones(
            default: snapZones,
            modifiers: snapModifierSets,
            held: WindowSnapState.shared.flags
        )
    }

    private func zone(at point: CGPoint) -> (NSScreen, SnapZone)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        guard let slot = SnapGeometry.slot(
            at: point,
            screen: screen.visibleFrame,
            corner: snapCorner,
            threshold: snapThreshold
        ) else { return nil }
        guard let zone = currentZones()[slot] else { return nil }
        return (screen, zone)
    }

    /// SnapPreview is shared with plugin grid previews. Do not hide it unless
    /// this is an actual window-edge drag; a click in a Macotron panel would
    /// otherwise steal the overlay.
    private static func hitsOwnWindow(_ point: CGPoint) -> Bool {
        NSApp.windows.contains { win in
            guard win.isVisible, !win.ignoresMouseEvents else { return false }
            return win.frame.contains(point)
        }
    }

    /// The event tap sees every left-drag on the machine, including a screenshot
    /// selection or a text selection. Those must not raise the snap overlay, so
    /// a drag only counts once the frontmost window has actually moved with it.
    /// The origin is sampled on the first drag event rather than on mouse-down,
    /// because macOS has not necessarily raised the clicked window by then.
    private func trackDraggedWindow() {
        let now = Date()
        let due = WindowSnapState.shared.withDrag { drag -> Bool in
            if drag.movedWindow { return false }
            if let last = drag.lastWindowCheck, now.timeIntervalSince(last) < 0.08 { return false }
            drag.lastWindowCheck = now
            return true
        }
        guard due, let win = Self.focusedAXWindow() else { return }
        let origin = WindowAX.frame(win).origin
        WindowSnapState.shared.withDrag { $0.sample(windowOrigin: origin) }
    }

    private func updateSnapPreview(at point: CGPoint) {
        if Self.hitsOwnWindow(point) { return }
        guard snapEnabled else { return }
        trackDraggedWindow()
        let live = WindowSnapState.shared.withDrag { $0.dragging && $0.movedWindow }
        guard live else { return }
        guard let hit = zone(at: point) else {
            SnapPreview.shared.hide()
            return
        }
        SnapPreview.shared.show(SnapGeometry.cocoaRect(zone: hit.1, visible: hit.0.visibleFrame, gap: snapGap))
    }

    private func finishSnap(at point: CGPoint, dragging: Bool) {
        if Self.hitsOwnWindow(point) { return }
        SnapPreview.shared.hide()
        guard dragging else { return }
        snapFocusedWindow(at: point)
    }

    private func snapFocusedWindow(at point: CGPoint) {
        guard snapEnabled else { return }
        guard let (screen, zone) = zone(at: point) else { return }
        guard let win = Self.focusedAXWindow() else { return }
        _ = Self.applyFraction(win, x: zone.x, y: zone.y, w: zone.w, h: zone.h, screen: screen, gap: snapGap)
    }

    func previewFraction(_ ctx: OpaquePointer, _ opts: JSValue) -> Bool {
        if engine?.dryRun == true { return true }
        var screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let display = JSBridge.int(ctx, opts, "display") {
            if let match = Self.screen(displayID: CGDirectDisplayID(bitPattern: Int32(truncatingIfNeeded: display))) {
                screen = match
            }
        } else if let win = Self.focusedAXWindow() {
            screen = Self.screen(forAXFrame: WindowAX.frame(win)) ?? screen
        }
        guard let screen else { return false }

        func num(_ key: String, _ fallback: CGFloat) -> CGFloat {
            JSBridge.double(ctx, opts, key).map { CGFloat($0) } ?? fallback
        }
        let zone = SnapZone(x: num("x", 0), y: num("y", 0), w: num("w", 1), h: num("h", 1))
        let gap = JSBridge.double(ctx, opts, "gap").map { max(0, CGFloat($0)) } ?? snapGap
        SnapPreview.shared.show(SnapGeometry.cocoaRect(zone: zone, visible: screen.visibleFrame, gap: gap))
        return true
    }

    func configureSnap(_ ctx: OpaquePointer, _ opts: JSValue) -> Bool {
        if JS_IsBool(opts) {
            return setSnapEnabled(JSBridge.toBool(ctx, opts))
        }
        let enabled = JSBridge.bool(ctx, opts, "enabled") ?? true
        if let threshold = JSBridge.double(ctx, opts, "threshold") {
            snapThreshold = max(1, CGFloat(threshold))
        }
        if let corner = JSBridge.double(ctx, opts, "corner") {
            snapCorner = max(1, CGFloat(corner))
        }
        if let gap = JSBridge.double(ctx, opts, "gap") {
            snapGap = max(0, CGFloat(gap))
        }

        let zonesVal = JSBridge.getProperty(ctx, opts, "zones")
        if JS_IsObject(zonesVal), !JSBridge.isUndefined(zonesVal), !JSBridge.isNull(zonesVal), !JS_IsArray(zonesVal) {
            if let dict = JSBridge.jsToSwift(ctx, zonesVal) as? [String: Any] {
                snapZones = SnapGeometry.parseZones(dict)
            }
        }
        JS_FreeValue(ctx, zonesVal)

        let modsVal = JSBridge.getProperty(ctx, opts, "modifiers")
        if JS_IsObject(modsVal), !JSBridge.isUndefined(modsVal), !JSBridge.isNull(modsVal), !JS_IsArray(modsVal) {
            if let dict = JSBridge.jsToSwift(ctx, modsVal) as? [String: Any] {
                snapModifierSets = SnapGeometry.parseModifierSets(dict)
            }
        } else if !JSBridge.isUndefined(modsVal), !JSBridge.isNull(modsVal) {
            snapModifierSets = []
        }
        JS_FreeValue(ctx, modsVal)

        return setSnapEnabled(enabled)
    }

    private static let axFocusTimeout: Float = 0.15

    private static func pid(of win: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        return pid
    }

    /// Focused window of another app. Skip Macotron: a key panel makes us the
    /// AX focused app, and asking for our own focused window can stall for seconds.
    private static func focusedAXWindow() -> AXUIElement? {
        let own = ProcessInfo.processInfo.processIdentifier
        if let win = axFocusedWindow(pid: nil), pid(of: win) != own {
            return win
        }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != own,
           let win = axFocusedWindow(pid: app.processIdentifier) {
            return win
        }
        return frontmostForeignWindow()
    }

    private static func axFocusedWindow(pid: pid_t?) -> AXUIElement? {
        let app: AXUIElement
        if let pid {
            app = AXUIElementCreateApplication(pid)
        } else {
            let sys = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(sys, axFocusTimeout)
            var appRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                sys,
                kAXFocusedApplicationAttribute as CFString,
                &appRef
            ) == .success, let appRef else { return nil }
            app = appRef as! AXUIElement
        }
        AXUIElementSetMessagingTimeout(app, axFocusTimeout)
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let winRef {
            return (winRef as! AXUIElement)
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            return windows.first
        }
        return nil
    }

    private static func frontmostForeignWindow() -> AXUIElement? {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for window in info {
            let pid = pid_t(window[kCGWindowOwnerPID as String] as? Int32 ?? 0)
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard pid != own, pid != 0, layer == 0 else { continue }
            if let win = axFocusedWindow(pid: pid) { return win }
        }
        return nil
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
        let currentFrame = WindowAX.frame(win)
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

        func setEnhancedUI(_ on: Bool) {
            guard let app else { return }
            let error = AXUIElementSetAttributeValue(
                app,
                "AXEnhancedUserInterface" as CFString,
                on ? kCFBooleanTrue : kCFBooleanFalse
            )
            if error != .success {
                logger.error("Failed to set AXEnhancedUserInterface: \(error.rawValue)")
            }
        }
        if enhancedUI == true { setEnhancedUI(false) }
        defer { if enhancedUI == true { setEnhancedUI(true) } }
        let firstSize = setWindowSize(win, size: size)
        let position = setWindowPosition(win, point: origin)
        let finalSize = setWindowSize(win, size: size)
        return firstSize || position || finalSize
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
