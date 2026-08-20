// GestureMonitor.swift — NSEvent swipe/magnify/rotate taps
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

struct GesturePayload: Sendable {
    let type: String
    let fingers: Int
    let direction: String
    let delta: Double
    let flags: [String]

    var jsObject: [String: Any] {
        [
            "type": type,
            "fingers": fingers,
            "direction": direction,
            "delta": delta,
            "flags": flags as [Any],
        ]
    }
}

enum GestureEvent {
    static func typeName(_ type: NSEvent.EventType) -> String? {
        switch type {
        case .swipe: return "swipe"
        case .magnify: return "magnify"
        case .rotate: return "rotate"
        default: return nil
        }
    }

    static func mask(for name: String) -> NSEvent.EventTypeMask? {
        switch name {
        case "swipe": return .swipe
        case "magnify": return .magnify
        case "rotate": return .rotate
        default: return nil
        }
    }

    static func direction(dx: Double, dy: Double) -> String {
        if abs(dx) >= abs(dy) {
            return dx >= 0 ? "right" : "left"
        }
        return dy >= 0 ? "up" : "down"
    }

    static func fingers(touchCount: Int, type: String) -> Int {
        if touchCount > 0 { return touchCount }
        switch type {
        case "swipe": return 3
        case "magnify", "rotate": return 2
        default: return 0
        }
    }

    static func payload(type: String, fingers: Int, dx: Double, dy: Double, delta: Double, flags: [String]) -> GesturePayload {
        GesturePayload(
            type: type,
            fingers: fingers,
            direction: type == "swipe" ? direction(dx: dx, dy: dy) : "",
            delta: delta,
            flags: flags
        )
    }

    static func payload(from event: NSEvent) -> GesturePayload? {
        guard let type = typeName(event.type) else { return nil }
        let delta: Double
        switch event.type {
        case .magnify: delta = Double(event.magnification)
        case .rotate: delta = Double(event.rotation)
        default: delta = 0
        }
        return payload(
            type: type,
            fingers: fingers(touchCount: event.touches(matching: .any, in: nil).count, type: type),
            dx: Double(event.deltaX),
            dy: Double(event.deltaY),
            delta: delta,
            flags: EventPost.flagNames(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        )
    }
}

private struct GestureListener: @unchecked Sendable {
    let mask: NSEvent.EventTypeMask
    let callback: JSValue
    let ctx: OpaquePointer
}

final class GestureMonitor: @unchecked Sendable {
    static let shared = GestureMonitor()

    weak var engine: Engine?

    private let lock = NSLock()
    private var listeners: [GestureListener] = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func add(mask: NSEvent.EventTypeMask, callback: JSValue, ctx: OpaquePointer) {
        lock.lock()
        listeners.append(GestureListener(mask: mask, callback: callback, ctx: ctx))
        lock.unlock()
        ensureMonitors()
    }

    func cleanup() {
        stopMonitors()
        lock.lock()
        let listeners = self.listeners
        self.listeners.removeAll()
        engine = nil
        lock.unlock()
        for listener in listeners {
            JS_FreeValue(listener.ctx, listener.callback)
        }
    }

    private func ensureMonitors() {
        lock.lock()
        let union = listeners.reduce(into: NSEvent.EventTypeMask()) { $0.formUnion($1.mask) }
        lock.unlock()
        guard !union.isEmpty else { return }
        stopMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: union) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: union) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func stopMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let payload = GestureEvent.payload(from: event) else { return }
        let bit = NSEvent.EventTypeMask(type: event.type)
        lock.lock()
        let listeners = self.listeners.filter { $0.mask.contains(bit) }
        lock.unlock()
        guard !listeners.isEmpty else { return }

        Task { @MainActor in
            guard let engine = self.engine, let ctx = engine.context else { return }
            let obj = JSBridge.newObject(ctx, payload.jsObject)
            for listener in listeners {
                var arg = obj
                let ret = JS_Call(ctx, listener.callback, QJS_Undefined(), 1, &arg)
                JS_FreeValue(ctx, ret)
            }
            JS_FreeValue(ctx, obj)
            engine.drainJobQueue()
        }
    }
}
