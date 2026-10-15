// PlayerModule.swift — macotron.player: play radio streams and podcasts
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class PlayerModule: NativeModule {
    public let name = "player"

    private weak var engine: Engine?

    public init() {}

    public func setUp(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__playerModule"] = self
        guard !engine.dryRun else { return }
        Player.shared.onChange = { [weak self] in self?.publish() }
    }

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let player = JS_NewObject(ctx)

        JSBridge.fn(ctx, player, "play", 2) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1,
                  let url = JSBridge.toString(ctx, argv[0]).flatMap(Player.playableURL)
            else { return JSBridge.newBool(ctx, false) }
            guard !Engine.isDryRun(ctx) else { return JSBridge.newBool(ctx, true) }
            let opts: JSValue? = argc >= 2 && JS_IsObject(argv[1]) ? argv[1] : nil
            Player.shared.play(
                url,
                title: opts.flatMap { JSBridge.string(ctx, $0, "title") },
                artist: opts.flatMap { JSBridge.string(ctx, $0, "artist") },
                artwork: opts.flatMap { JSBridge.string(ctx, $0, "artwork") },
                position: opts.flatMap { JSBridge.double(ctx, $0, "position") }
            )
            return JSBridge.newBool(ctx, true)
        }

        JSBridge.fn(ctx, player, "pause", 0) { ctx, _, _, _ in
            if !Engine.isDryRun(ctx) { Player.shared.pause() }
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "resume", 0) { ctx, _, _, _ in
            if !Engine.isDryRun(ctx) { Player.shared.resume() }
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "toggle", 0) { ctx, _, _, _ in
            if !Engine.isDryRun(ctx) { Player.shared.toggle() }
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "stop", 0) { ctx, _, _, _ in
            if !Engine.isDryRun(ctx) { Player.shared.stop() }
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "seek", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, !Engine.isDryRun(ctx) else { return QJS_Undefined() }
            Player.shared.seek(JSBridge.toDouble(ctx, argv[0]))
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "setVolume", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, !Engine.isDryRun(ctx) else { return QJS_Undefined() }
            Player.shared.setVolume(JSBridge.toDouble(ctx, argv[0]))
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, player, "state", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            let state = Engine.isDryRun(ctx) ? PlayerState() : Player.shared.state()
            return JSBridge.newObject(ctx, state.js)
        }

        JS_SetPropertyStr(ctx, macotron, "player", player)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    // Playback carries on across reloads; only the listener goes.
    public func cleanup() {
        Player.shared.onChange = nil
        engine = nil
    }

    private func publish() {
        guard let engine, let ctx = engine.context else { return }
        let data = JSBridge.newObject(ctx, Player.shared.state().js)
        engine.eventBus.emit("player:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }
}
