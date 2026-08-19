// AudioModule.swift — macotron.audio: devices, defaults, volume, audio:changed
import CQuickJS
import CoreAudio
import Foundation
import MacotronEngine

@MainActor
public final class AudioModule: NativeModule {
    public let name = "audio"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__audioModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let audio = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, audio, "devices", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, AudioDevices.list().map(\.js))
        }, "devices", 0))

        JS_SetPropertyStr(ctx, audio, "input", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let dev = AudioDevices.input() else { return QJS_Null() }
            return JSBridge.newObject(ctx, dev.js)
        }, "input", 0))

        JS_SetPropertyStr(ctx, audio, "output", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let dev = AudioDevices.output() else { return QJS_Null() }
            return JSBridge.newObject(ctx, dev.js)
        }, "output", 0))

        JS_SetPropertyStr(ctx, audio, "setInput", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, AudioModule.setDefault(ctx, argv[0], input: true))
        }, "setInput", 1))

        JS_SetPropertyStr(ctx, audio, "setOutput", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, AudioModule.setDefault(ctx, argv[0], input: false))
        }, "setOutput", 1))

        JS_SetPropertyStr(ctx, audio, "volume", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let id = AudioModule.deviceID(ctx, argc > 0 ? argv?[0] : nil) ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id, let vol = AudioDevices.volume(id: id) else { return QJS_Null() }
            return JSBridge.newFloat64(ctx, vol)
        }, "volume", 1))

        JS_SetPropertyStr(ctx, audio, "setVolume", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            let value = JSBridge.toDouble(ctx, argv[0])
            let id = (argc > 1 ? AudioModule.deviceID(ctx, argv[1]) : nil)
                ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AudioDevices.setVolume(id: id, value))
        }, "setVolume", 2))

        JS_SetPropertyStr(ctx, audio, "isMuted", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            let id = AudioModule.deviceID(ctx, argc > 0 ? argv?[0] : nil)
                ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AudioDevices.isMuted(id: id))
        }, "isMuted", 1))

        JS_SetPropertyStr(ctx, audio, "setMuted", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            let on = JSBridge.toBool(ctx, argv[0])
            let id = (argc > 1 ? AudioModule.deviceID(ctx, argv[1]) : nil)
                ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AudioDevices.setMuted(id: id, on))
        }, "setMuted", 2))

        JS_SetPropertyStr(ctx, macotron, "audio", audio)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        AudioWatch.start(engine)
    }

    public func cleanup() {
        AudioWatch.stop()
    }

    fileprivate static func setDefault(_ ctx: OpaquePointer, _ spec: JSValue, input: Bool) -> Bool {
        guard let id = deviceID(ctx, spec) else { return false }
        return AudioDevices.setDefault(id: id, input: input)
    }

    fileprivate static func deviceID(_ ctx: OpaquePointer, _ spec: JSValue?) -> AudioDeviceID? {
        guard let spec, !JSBridge.isUndefined(spec), !JSBridge.isNull(spec) else { return nil }
        if JS_IsNumber(spec) {
            let id = AudioDeviceID(UInt32(bitPattern: JSBridge.toInt32(ctx, spec)))
            return AudioDevices.find(id: id).map { AudioDeviceID($0.id) }
        }
        if let name = JSBridge.toString(ctx, spec) {
            return AudioDevices.find(name).map { AudioDeviceID($0.id) }
        }
        return nil
    }
}
