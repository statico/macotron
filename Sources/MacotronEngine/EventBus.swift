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
    /// Emit an event, calling all registered callbacks.
    ///
    /// `budget` overrides the default time each listener gets before the engine
    /// interrupts it — pass `Engine.inputBudget` from anything on an input path.
    public func emit(
        _ event: String,
        engine: Engine,
        data: JSValue? = nil,
        budget: TimeInterval? = nil
    ) {
        guard let callbacks = listeners[event] else { return }
        // A listener is allowed to unsubscribe itself -- listen once, then off()
        // -- and off() releases the callback. Hold a reference to each one for
        // the length of the loop so that frees nothing still to be called.
        let held = callbacks.map { (ctx: $0.ctx, callback: JS_DupValue($0.ctx, $0.callback)) }
        defer { for h in held { JS_FreeValue(h.ctx, h.callback) } }

        for listener in held {
            let result = engine.callJS(
                listener.callback,
                data.map { [$0] } ?? [],
                budget: budget,
                label: "event \(event)",
                drain: false
            )
            if let result { JS_FreeValue(engine.context, result) }
        }
        engine.drainJobQueue(budget: budget)
    }

    /// Whether any callback is registered for an event
    public func hasListeners(_ event: String) -> Bool {
        listeners[event]?.isEmpty == false
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
