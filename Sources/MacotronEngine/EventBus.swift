// EventBus.swift — Unified event dispatch: native macOS events → JS callbacks
import CQuickJS
import Foundation

@MainActor
public final class EventBus {
    public struct Listener {
        let callback: JSValue  // DupValue'd to prevent GC
        let ctx: OpaquePointer
    }

    private var listeners: [String: [Listener]] = [:]

    public init() {}

    /// Register a JS callback for an event
    public func on(_ event: String, callback: JSValue, ctx: OpaquePointer) {
        let protected = JS_DupValue(ctx, callback)
        listeners[event, default: []].append(Listener(callback: protected, ctx: ctx))
    }

    /// Remove a specific callback for an event (by reference equality)
    public func off(_ event: String, callback: JSValue, ctx: OpaquePointer) {
        guard var list = listeners[event] else { return }
        list.removeAll { listener in
            // Compare by JS value tag+payload
            let same = (listener.callback.tag == callback.tag && listener.callback.u.ptr == callback.u.ptr)
            if same {
                JS_FreeValue(listener.ctx, listener.callback)
            }
            return same
        }
        listeners[event] = list.isEmpty ? nil : list
    }

    /// Emit an event, calling all registered callbacks
    public func emit(_ event: String, engine: Engine, data: JSValue? = nil) {
        guard let callbacks = listeners[event] else { return }
        for listener in callbacks {
            if let data {
                var args = [data]
                _ = JS_Call(engine.context, listener.callback, QJS_Undefined(), 1, &args)
            } else {
                _ = JS_Call(engine.context, listener.callback, QJS_Undefined(), 0, nil)
            }
        }
        engine.drainJobQueue()
    }

    /// Check if any listeners exist for an event
    public func hasListeners(for event: String) -> Bool {
        guard let list = listeners[event] else { return false }
        return !list.isEmpty
    }

    /// Remove all listeners (called on reload)
    public func removeAllListeners() {
        for (_, list) in listeners {
            for listener in list {
                JS_FreeValue(listener.ctx, listener.callback)
            }
        }
        listeners.removeAll()
    }
}
