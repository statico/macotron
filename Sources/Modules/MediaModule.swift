import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class MediaModule: NativeModule {
    public let name = "media"

    private weak var engine: Engine?
    private var timer: Timer?
    private var lastFingerprint = ""

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__mediaModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let media = JS_NewObject(ctx)

        JSBridge.fn(ctx, media, "nowPlaying", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, NowPlaying.shared.snapshot().js)
        }

        JSBridge.fn(ctx, media, "playPause", 0) { ctx, _, _, _ in
            NowPlaying.shared.send(.togglePlayPause)
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, media, "next", 0) { ctx, _, _, _ in
            NowPlaying.shared.send(.nextTrack)
            return QJS_Undefined()
        }

        JSBridge.fn(ctx, media, "previous", 0) { ctx, _, _, _ in
            NowPlaying.shared.send(.previousTrack)
            return QJS_Undefined()
        }

        JS_SetPropertyStr(ctx, macotron, "media", media)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        NowPlaying.shared.onChange = { [weak self] in
            DispatchQueue.main.async { self?.publish() }
        }
        NowPlaying.shared.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            NowPlaying.shared.refresh()
        }
    }

    public func cleanup() {
        timer?.invalidate()
        timer = nil
        NowPlaying.shared.onChange = nil
        engine = nil
    }

    private func publish() {
        let snap = NowPlaying.shared.snapshot()
        guard snap.fingerprint != lastFingerprint else { return }
        lastFingerprint = snap.fingerprint
        guard let engine, let ctx = engine.context else { return }
        let data = JSBridge.newObject(ctx, snap.js)
        engine.eventBus.emit("media:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }
}
