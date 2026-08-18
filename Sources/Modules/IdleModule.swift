// IdleModule.swift — macotron.idle: idle seconds + system:idle / system:active
import CQuickJS
import CoreGraphics
import Foundation
import MacotronEngine

@MainActor
public final class IdleModule: NativeModule {
    public let name = "idle"

    private weak var engine: Engine?
    private var timer: Timer?
    private var threshold: Double = 60
    private var isIdle = false

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__idleModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let idle = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, idle, "seconds", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newFloat64(ctx, IdleModule.idleSeconds())
        }, "seconds", 0))

        JS_SetPropertyStr(ctx, idle, "setThreshold", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let opaque = JS_GetContextOpaque(ctx) else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            (engine.configStore["__idleModule"] as? IdleModule)?.threshold = JSBridge.toDouble(ctx, argv[0])
            return QJS_Undefined()
        }, "setThreshold", 1))

        JS_SetPropertyStr(ctx, macotron, "idle", idle)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func cleanup() {
        timer?.invalidate()
        timer = nil
        engine = nil
    }

    private func poll() {
        let seconds = IdleModule.idleSeconds()
        let nowIdle = seconds >= threshold
        guard nowIdle != isIdle, let engine else { return }
        isIdle = nowIdle
        engine.eventBus.emit(nowIdle ? "system:idle" : "system:active", engine: engine)
    }

    private static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
    }
}
