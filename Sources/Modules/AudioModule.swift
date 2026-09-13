// AudioModule.swift — macotron.audio: devices, defaults, volume, audio:changed
import AVFoundation
import CQuickJS
import CoreAudio
import Foundation
import MacotronEngine

@MainActor
public final class AudioModule: NativeModule {
    public let name = "audio"
    public let moduleVersion = 1

    private var recorder: AVAudioRecorder?
    private var recordURL: URL?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__audioModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let audio = JS_NewObject(ctx)

        JSBridge.fn(ctx, audio, "devices", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, AudioDevices.list().map(\.js))
        }

        JSBridge.fn(ctx, audio, "input", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let dev = AudioDevices.input() else { return QJS_Null() }
            return JSBridge.newObject(ctx, dev.js)
        }

        JSBridge.fn(ctx, audio, "output", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            guard let dev = AudioDevices.output() else { return QJS_Null() }
            return JSBridge.newObject(ctx, dev.js)
        }

        JSBridge.fn(ctx, audio, "setInput", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, AudioModule.setDefault(ctx, argv[0], input: true))
        }

        JSBridge.fn(ctx, audio, "setOutput", 1) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, AudioModule.setDefault(ctx, argv[0], input: false))
        }

        JSBridge.fn(ctx, audio, "volume", 1) { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            let id = AudioModule.deviceID(ctx, argc > 0 ? argv?[0] : nil) ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id, let vol = AudioDevices.volume(id: id) else { return QJS_Null() }
            return JSBridge.newFloat64(ctx, vol)
        }

        JSBridge.fn(ctx, audio, "setVolume", 2) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            let value = JSBridge.toDouble(ctx, argv[0])
            let id = (argc > 1 ? AudioModule.deviceID(ctx, argv[1]) : nil)
                ?? AudioDevices.output().map { AudioDeviceID($0.id) }
            guard let id else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AudioDevices.setVolume(id: id, value))
        }

        JSBridge.fn(ctx, audio, "isMuted", 1) { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            let explicit = argc > 0 ? AudioModule.deviceID(ctx, argv?[0]) : nil
            if let id = explicit {
                let preferInput = AudioDevices.find(id: id)?.input == true
                return JSBridge.newBool(ctx, AudioDevices.isMuted(id: id, preferInput: preferInput))
            }
            guard let id = AudioDevices.output().map({ AudioDeviceID($0.id) }) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, AudioDevices.isMuted(id: id, preferInput: false))
        }

        JSBridge.fn(ctx, audio, "setMuted", 2) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return JSBridge.newBool(ctx!, false) }
            let on = JSBridge.toBool(ctx, argv[0])
            let explicit = argc > 1 ? AudioModule.deviceID(ctx, argv[1]) : nil
            if let id = explicit {
                let preferInput = AudioDevices.find(id: id)?.input == true
                return JSBridge.newBool(ctx, AudioDevices.setMuted(id: id, on, preferInput: preferInput))
            }
            guard let id = AudioDevices.output().map({ AudioDeviceID($0.id) }) else {
                return JSBridge.newBool(ctx, false)
            }
            return JSBridge.newBool(ctx, AudioDevices.setMuted(id: id, on, preferInput: false))
        }

        JSBridge.fn(ctx, audio, "record", 1) { ctx, _, argc, argv in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            if Engine.isDryRun(ctx) { return JSBridge.newBool(ctx, false) }
            guard let argv, argc >= 1 else { return JSBridge.newBool(ctx, false) }
            guard let path = JSBridge.string(ctx, argv[0], "path"), !path.isEmpty else { return JSBridge.newBool(ctx, false) }
            return JSBridge.newBool(ctx, AudioModule.module(ctx)?.record(path) ?? false)
        }

        JSBridge.fn(ctx, audio, "stopRecord", 0) { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Null() }
            guard let result = AudioModule.module(ctx)?.stopRecord() else { return QJS_Null() }
            return JSBridge.newObject(ctx, result)
        }

        JSBridge.fn(ctx, audio, "isRecording", 0) { ctx, _, _, _ in
            guard let ctx else { return JSBridge.newBool(ctx!, false) }
            return JSBridge.newBool(ctx, AudioModule.module(ctx)?.recorder?.isRecording ?? false)
        }

        JS_SetPropertyStr(ctx, macotron, "audio", audio)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        AudioWatch.start(engine)
    }

    public func cleanup() {
        recorder?.stop()
        recorder = nil
        recordURL = nil
        AudioWatch.stop()
    }

    fileprivate func record(_ path: String) -> Bool {
        _ = stopRecord()
        let url = URL(fileURLWithPath: SharePath.expand(path))
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return false }
        recorder.prepareToRecord()
        guard recorder.record() else { return false }
        self.recorder = recorder
        recordURL = url
        return true
    }

    fileprivate func stopRecord() -> [String: Any]? {
        guard let recorder, let recordURL else { return nil }
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordURL = nil
        return ["path": recordURL.path, "seconds": seconds]
    }

    fileprivate static func module(_ ctx: OpaquePointer) -> AudioModule? {
        Engine.module(ctx, "__audioModule")
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
