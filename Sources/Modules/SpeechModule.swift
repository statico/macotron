// SpeechModule.swift — macotron.speech: speak text aloud
import AVFoundation
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
enum Speech {
    /// One synthesizer for every plugin: it has to outlive the call that
    /// queued the speech, and sharing it queues announcements instead of
    /// talking over each other.
    static let synthesizer = AVSpeechSynthesizer()

    /// A voice by identifier (`com.apple.voice.compact.en-US.Samantha`) or by
    /// display name (`Samantha`); nil leaves the system default.
    static func voice(_ name: String?, in voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        guard let name, !name.isEmpty else { return nil }
        return voices.first { $0.identifier == name }
            ?? voices.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func say(_ text: String, voice name: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(name, in: AVSpeechSynthesisVoice.speechVoices())
        synthesizer.speak(utterance)
    }
}

@MainActor
public final class SpeechModule: NativeModule {
    public let name = "speech"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let speech = JS_NewObject(ctx)

        JSBridge.fn(ctx, speech, "say", 2) { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let text = JSBridge.toString(ctx, argv[0]), !text.isEmpty,
                  !Engine.isDryRun(ctx) else { return QJS_Undefined() }
            let voice = argc >= 2 && JS_IsObject(argv[1]) ? JSBridge.string(ctx, argv[1], "voice") : nil
            Speech.say(text, voice: voice)
            return QJS_Undefined()
        }

        JS_SetPropertyStr(ctx, macotron, "speech", speech)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
