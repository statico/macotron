// AsyncBridge.swift — turn blocking native work into a JS promise
import CQuickJS
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "engine")

/// Result of one async bridge: whatever `JSBridge.anyToJS` can convert, or a
/// message to reject with.
public enum BridgeResult {
    case value(Any)
    case failure(String)

    /// `nil` resolves to `undefined`, which is what most void bridges want.
    public static func of(_ value: Any?) -> BridgeResult {
        value.map { .value($0) } ?? .value(NSNull())
    }
}

extension JSBridge {
    /// Run blocking work off the main thread and settle a JS promise with it.
    ///
    /// Every async module bridge wants this exact shape, and hand-rolling it is
    /// ~40 lines of promise-capability and refcount bookkeeping per call site —
    /// which is how you end up with twenty subtly different versions of it.
    ///
    /// `dryRun` is what the promise resolves to when the engine is stubbing side
    /// effects, so `--check` never touches the network, a subprocess, or a store.
    ///
    /// The `work` closure runs on a global queue; do not touch AppKit, the JS
    /// context, or any `@MainActor` state inside it.
    public static func promise(
        _ ctx: OpaquePointer,
        dryRun: Any? = nil,
        qos: DispatchQoS.QoSClass = .userInitiated,
        _ work: @escaping @Sendable () -> BridgeResult
    ) -> JSValue {
        var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
        let promise = JS_NewPromiseCapability(ctx, &resolving)
        let resolve = JS_DupValue(ctx, resolving[0])
        let reject = JS_DupValue(ctx, resolving[1])
        JS_FreeValue(ctx, resolving[0])
        JS_FreeValue(ctx, resolving[1])

        guard let engine = Engine.of(ctx) else {
            JS_FreeValue(ctx, resolve)
            JS_FreeValue(ctx, reject)
            return promise
        }

        if engine.dryRun {
            settle(ctx, engine: engine, resolve: resolve, reject: reject,
                   with: .of(dryRun))
            return promise
        }

        let token = engine.registerPending(resolve: resolve, reject: reject)
        nonisolated(unsafe) let capturedCtx = ctx
        DispatchQueue.global(qos: qos).async {
            let outcome = work()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // nil means reset() already rejected and freed this promise
                    // while the work was in flight: drop the stale result.
                    guard let pending = engine.claimPending(token) else { return }
                    settle(capturedCtx, engine: engine,
                           resolve: pending.resolve, reject: pending.reject, with: outcome)
                }
            }
        }
        return promise
    }

    /// Settle and free one promise's capability pair. Takes ownership of both.
    @MainActor
    private static func settle(
        _ ctx: OpaquePointer,
        engine: Engine,
        resolve: JSValue,
        reject: JSValue,
        with outcome: BridgeResult
    ) {
        switch outcome {
        case .value(let any):
            let value = anyToJS(ctx, any)
            if let result = engine.callJS(resolve, [value], label: "promise resolve", drain: false) {
                JS_FreeValue(ctx, result)
            }
            JS_FreeValue(ctx, value)
        case .failure(let message):
            let value = newString(ctx, message)
            if let result = engine.callJS(reject, [value], label: "promise reject", drain: false) {
                JS_FreeValue(ctx, result)
            }
            JS_FreeValue(ctx, value)
        }
        JS_FreeValue(ctx, resolve)
        JS_FreeValue(ctx, reject)
        engine.drainJobQueue()
    }
}

extension JSBridge {
    /// A promise settled later, from the main thread, by whoever holds the
    /// returned closure. `promise` covers work that runs; this covers work that
    /// is waited for — a device report, a callback, an event — where there is
    /// nothing to put on a background queue.
    ///
    /// The closure is a no-op after the first call, and after `reset()` has
    /// rejected the promise out from under it.
    @MainActor
    public static func deferred(
        _ ctx: OpaquePointer,
        dryRun: Any? = nil
    ) -> (promise: JSValue, settle: @MainActor (BridgeResult) -> Void) {
        var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
        let promise = JS_NewPromiseCapability(ctx, &resolving)
        let resolve = JS_DupValue(ctx, resolving[0])
        let reject = JS_DupValue(ctx, resolving[1])
        JS_FreeValue(ctx, resolving[0])
        JS_FreeValue(ctx, resolving[1])

        guard let engine = Engine.of(ctx) else {
            JS_FreeValue(ctx, resolve)
            JS_FreeValue(ctx, reject)
            return (promise, { _ in })
        }

        if engine.dryRun {
            settle(ctx, engine: engine, resolve: resolve, reject: reject, with: .of(dryRun))
            return (promise, { _ in })
        }

        let token = engine.registerPending(resolve: resolve, reject: reject)
        return (promise, { outcome in
            guard let pending = engine.claimPending(token) else { return }
            settle(ctx, engine: engine,
                   resolve: pending.resolve, reject: pending.reject, with: outcome)
        })
    }
}
