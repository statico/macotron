// EventModule.swift — macotron.event / macotron.mouse: HID post and taps
import AppKit
import CQuickJS
import CoreGraphics
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "event")
private let syntheticTag: Int64 = 0x4D41434F // MACO

enum EventPost {
    static let userDataField = CGEventField.eventSourceUserData

    static func modifierFlags(_ names: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for name in names {
            switch name.lowercased() {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            case "caps", "capslock": flags.insert(.maskAlphaShift)
            default: break
            }
        }
        return flags
    }

    static func flagNames(_ flags: CGEventFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.maskCommand) { names.append("cmd") }
        if flags.contains(.maskShift) { names.append("shift") }
        if flags.contains(.maskControl) { names.append("ctrl") }
        if flags.contains(.maskAlternate) { names.append("opt") }
        if flags.contains(.maskSecondaryFn) { names.append("fn") }
        if flags.contains(.maskAlphaShift) { names.append("caps") }
        return names
    }

    static func mouseButton(_ name: String) -> CGMouseButton {
        switch name.lowercased() {
        case "right": return .right
        case "middle", "center": return .center
        default: return .left
        }
    }

    static func tapMask(for name: String) -> CGEventMask? {
        let type: CGEventType
        switch name {
        case "flagsChanged": type = .flagsChanged
        case "scroll", "scrollWheel": type = .scrollWheel
        case "leftMouseDown": type = .leftMouseDown
        case "leftMouseUp": type = .leftMouseUp
        case "rightMouseDown": type = .rightMouseDown
        case "rightMouseUp": type = .rightMouseUp
        case "mouseMoved": type = .mouseMoved
        case "leftMouseDragged": type = .leftMouseDragged
        case "keyDown": type = .keyDown
        case "keyUp": type = .keyUp
        default: return nil
        }
        return 1 << type.rawValue
    }

    static func typeName(_ type: CGEventType) -> String {
        switch type {
        case .flagsChanged: return "flagsChanged"
        case .scrollWheel: return "scroll"
        case .leftMouseDown: return "leftMouseDown"
        case .leftMouseUp: return "leftMouseUp"
        case .rightMouseDown: return "rightMouseDown"
        case .rightMouseUp: return "rightMouseUp"
        case .mouseMoved: return "mouseMoved"
        case .leftMouseDragged: return "leftMouseDragged"
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        default: return "other"
        }
    }
}

private struct EventTapListener {
    let mask: CGEventMask
    let callback: JSValue
    let ctx: OpaquePointer
}

private final class EventTapState: @unchecked Sendable {
    static let shared = EventTapState()
    let lock = NSLock()
    var listeners: [EventTapListener] = []
    weak var engine: Engine?
    weak var module: EventModule?
    var eventTap: CFMachPort?
}

@MainActor
public final class EventModule: NativeModule {
    public let name = "event"
    public let moduleVersion = 1

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        EventTapState.shared.engine = engine
        EventTapState.shared.module = self
        GestureMonitor.shared.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let eventObj = JS_NewObject(ctx)
        JS_SetPropertyStr(ctx, eventObj, "post", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            if EventModule.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            let raw = JSBridge.jsToSwift(ctx, argv[0])
            guard let dict = raw as? [String: Any] else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, EventModule.post(dict))
        }, "post", 1))

        JS_SetPropertyStr(ctx, eventObj, "tap", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2, JS_IsFunction(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "event.tap(types, callback)")
            }
            if EventModule.isDryRun(ctx) { return QJS_Undefined() }
            var mask: CGEventMask = 0
            var gestureMask = NSEvent.EventTypeMask()
            let typesVal = JSBridge.jsToSwift(ctx, argv[0])
            let names: [String]
            if let arr = typesVal as? [Any] {
                names = arr.compactMap { $0 as? String }
            } else if let one = typesVal as? String {
                names = [one]
            } else {
                names = []
            }
            for name in names {
                if let bit = EventPost.tapMask(for: name) {
                    mask |= bit
                } else if let bit = GestureEvent.mask(for: name) {
                    gestureMask.insert(bit)
                }
            }
            guard mask != 0 || !gestureMask.isEmpty else { return QJS_Undefined() }
            if mask != 0 {
                let listener = EventTapListener(mask: mask, callback: JS_DupValue(ctx, argv[1]), ctx: ctx)
                let state = EventTapState.shared
                state.lock.lock()
                state.listeners.append(listener)
                state.lock.unlock()
                state.module?.ensureTap()
            }
            if !gestureMask.isEmpty {
                GestureMonitor.shared.add(mask: gestureMask, callback: JS_DupValue(ctx, argv[1]), ctx: ctx)
            }
            return QJS_Undefined()
        }, "tap", 2))

        JS_SetPropertyStr(ctx, macotron, "event", eventObj)

        let mouseObj = JS_NewObject(ctx)
        JS_SetPropertyStr(ctx, mouseObj, "location", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let p = NSEvent.mouseLocation
            return JSBridge.newObject(ctx, ["x": Double(p.x), "y": Double(p.y)])
        }, "location", 0))

        JS_SetPropertyStr(ctx, mouseObj, "warp", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            if EventModule.isDryRun(ctx) { return JSBridge.newBool(ctx, true) }
            let x: Double
            let y: Double
            if JS_IsObject(argv[0]) {
                let xv = JSBridge.getProperty(ctx, argv[0], "x")
                let yv = JSBridge.getProperty(ctx, argv[0], "y")
                x = JSBridge.toDouble(ctx, xv)
                y = JSBridge.toDouble(ctx, yv)
                JS_FreeValue(ctx, xv)
                JS_FreeValue(ctx, yv)
            } else {
                guard argc >= 2 else { return JSBridge.newBool(ctx, false) }
                x = JSBridge.toDouble(ctx, argv[0])
                y = JSBridge.toDouble(ctx, argv[1])
            }
            EventModule.warp(CGPoint(x: x, y: y))
            return JSBridge.newBool(ctx, true)
        }, "warp", 2))

        JS_SetPropertyStr(ctx, mouseObj, "buttons", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, [
                "left": CGEventSource.buttonState(.hidSystemState, button: .left),
                "right": CGEventSource.buttonState(.hidSystemState, button: .right),
                "center": CGEventSource.buttonState(.hidSystemState, button: .center),
            ])
        }, "buttons", 0))

        JS_SetPropertyStr(ctx, macotron, "mouse", mouseObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        teardownTap()
        GestureMonitor.shared.cleanup()
        let state = EventTapState.shared
        state.lock.lock()
        let listeners = state.listeners
        state.listeners.removeAll()
        state.engine = nil
        state.module = nil
        state.lock.unlock()
        for listener in listeners {
            JS_FreeValue(listener.ctx, listener.callback)
        }
    }

    private static func isDryRun(_ ctx: OpaquePointer) -> Bool {
        guard let opaque = JS_GetContextOpaque(ctx) else { return false }
        return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
    }

    static func post(_ dict: [String: Any]) -> Bool {
        switch (dict["type"] as? String)?.lowercased() ?? "" {
        case "click": return postClick(dict)
        case "key": return postKey(dict)
        case "unicode": return postUnicode(dict)
        case "scroll": return postScroll(dict)
        default: return false
        }
    }

    private static func mark(_ event: CGEvent) {
        event.setIntegerValueField(EventPost.userDataField, value: syntheticTag)
    }

    private static func cocoaPoint(_ dict: [String: Any]) -> CGPoint {
        if let x = double(dict, "x"), let y = double(dict, "y") {
            return CGPoint(x: x, y: y)
        }
        return NSEvent.mouseLocation
    }

    private static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let d = dict[key] as? Double { return d }
        if let i = dict[key] as? Int { return Double(i) }
        if let i = dict[key] as? Int32 { return Double(i) }
        return nil
    }

    private static func stringArray(_ dict: [String: Any], _ key: String) -> [String] {
        if let arr = dict[key] as? [String] { return arr }
        if let arr = dict[key] as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    private static func postClick(_ dict: [String: Any]) -> Bool {
        let button = EventPost.mouseButton(dict["button"] as? String ?? "left")
        let pt = cocoaPoint(dict)
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .right:
            downType = .rightMouseDown
            upType = .rightMouseUp
        case .center:
            downType = .otherMouseDown
            upType = .otherMouseUp
        default:
            downType = .leftMouseDown
            upType = .leftMouseUp
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: pt, mouseButton: button),
              let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: pt, mouseButton: button) else {
            return false
        }
        mark(down)
        mark(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func postKey(_ dict: [String: Any]) -> Bool {
        let key = dict["key"] as? String ?? ""
        let names = stringArray(dict, "flags")
        let flags = EventPost.modifierFlags(names)
        var comboStr = names.joined(separator: "+")
        if !comboStr.isEmpty { comboStr += "+" }
        comboStr += key
        guard let combo = KeyCombo.parse(comboStr.isEmpty ? key : comboStr) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) else {
            return false
        }
        down.flags = flags.isEmpty ? combo.modifiers : flags
        up.flags = down.flags
        mark(down)
        mark(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func postUnicode(_ dict: [String: Any]) -> Bool {
        let string = dict["string"] as? String ?? ""
        guard !string.isEmpty else { return false }
        let chars = Array(string.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        mark(down)
        mark(up)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func postScroll(_ dict: [String: Any]) -> Bool {
        let dy = Int32(double(dict, "dy") ?? double(dict, "y") ?? 0)
        let dx = Int32(double(dict, "dx") ?? double(dict, "x") ?? 0)
        let pixel = dict["pixel"] as? Bool ?? false
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: pixel ? .pixel : .line,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else { return false }
        mark(event)
        event.post(tap: .cghidEventTap)
        return true
    }

    static func warp(_ cocoa: CGPoint) {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        let quartz = CGPoint(x: cocoa.x, y: height - cocoa.y)
        CGWarpMouseCursorPosition(quartz)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    fileprivate func ensureTap() {
        let state = EventTapState.shared
        state.lock.lock()
        let union = state.listeners.reduce(CGEventMask(0)) { $0 | $1.mask }
        state.lock.unlock()
        guard union != 0 else { return }
        teardownTap()
        setupTap(mask: union)
    }

    private func teardownTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        EventTapState.shared.eventTap = nil
    }

    private func setupTap(mask: CGEventMask) {
        guard eventTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = EventTapState.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            if event.getIntegerValueField(EventPost.userDataField) == syntheticTag {
                return Unmanaged.passRetained(event)
            }
            let bit: CGEventMask = 1 << type.rawValue
            let state = EventTapState.shared
            state.lock.lock()
            let listeners = state.listeners.filter { $0.mask & bit != 0 }
            state.lock.unlock()
            guard !listeners.isEmpty else { return Unmanaged.passRetained(event) }

            var swallow = false
            let run = { @MainActor in
                guard let engine = EventTapState.shared.engine, let ctx = engine.context else { return }
                let loc = event.location
                var payload: [String: Any] = [
                    "type": EventPost.typeName(type),
                    "flags": EventPost.flagNames(event.flags) as [Any],
                    "x": Double(loc.x),
                    "y": Double(loc.y),
                ]
                if type == .keyDown || type == .keyUp {
                    payload["keyCode"] = Int(event.getIntegerValueField(.keyboardEventKeycode))
                }
                if type == .scrollWheel {
                    payload["dy"] = Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
                    payload["dx"] = Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
                }
                if type == .leftMouseDown || type == .leftMouseUp {
                    payload["button"] = "left"
                    payload["down"] = type == .leftMouseDown
                }
                if type == .rightMouseDown || type == .rightMouseUp {
                    payload["button"] = "right"
                    payload["down"] = type == .rightMouseDown
                }
                let obj = JSBridge.newObject(ctx, payload)
                for listener in listeners {
                    // inputBudget, not the default: this runs inside the event
                    // tap callback, so every millisecond here is a millisecond
                    // of stalled input for the entire system.
                    let ret = engine.callJS(
                        listener.callback, [obj],
                        budget: Engine.inputBudget, label: "event.on tap", drain: false
                    )
                    guard let ret else { continue }
                    if JS_IsBool(ret), JSBridge.toBool(ctx, ret) == false {
                        swallow = true
                    }
                    JS_FreeValue(ctx, ret)
                }
                JS_FreeValue(ctx, obj)
                engine.drainJobQueue(budget: Engine.inputBudget)
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated(run)
            } else {
                DispatchQueue.main.sync { MainActor.assumeIsolated(run) }
            }
            return swallow ? nil : Unmanaged.passRetained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            logger.error("event.tap: failed to create CGEvent tap")
            return
        }
        eventTap = tap
        EventTapState.shared.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
