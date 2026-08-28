// AIModule.swift — macotron.ai: AI provider namespace with chat/stream methods
import AI
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class AIModule: NativeModule {
    public let name = "ai"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let aiObj = JS_NewObject(ctx)

        // macotron.ai.claude(opts?) → AI client object
        JS_SetPropertyStr(ctx, aiObj, "claude", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            return AIModule.client(ctx, "claude", argc, argv)
        }, "claude", 1))
        let claudeFn = JS_GetPropertyStr(ctx, aiObj, "claude")
        JS_SetPropertyStr(ctx, aiObj, "anthropic", JS_DupValue(ctx, claudeFn))
        JS_FreeValue(ctx, claudeFn)

        JS_SetPropertyStr(ctx, aiObj, "openai", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            return AIModule.client(ctx, "openai", argc, argv)
        }, "openai", 1))

        JS_SetPropertyStr(ctx, aiObj, "gemini", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            return AIModule.client(ctx, "gemini", argc, argv)
        }, "gemini", 1))

        // local takes no key or model: it is whatever is running on this Mac.
        JS_SetPropertyStr(ctx, aiObj, "local", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return AIModule.createClientObject(
                ctx: ctx, providerName: "local", apiKey: nil, model: nil
            )
        }, "local", 0))

        JS_SetPropertyStr(ctx, macotron, "ai", aiObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    // MARK: - Client Object Builder

    /// Create a JS object with .chat and .stream methods.
    @MainActor
    fileprivate static func createClientObject(
        ctx: OpaquePointer,
        providerName: String,
        apiKey: String?,
        model: String?
    ) -> JSValue {
        let clientObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, clientObj, "_provider", JSBridge.newString(ctx, providerName))
        if let apiKey {
            JS_SetPropertyStr(ctx, clientObj, "_apiKey", JSBridge.newString(ctx, apiKey))
        }
        if let model {
            JS_SetPropertyStr(ctx, clientObj, "_model", JSBridge.newString(ctx, model))
        }

        JS_SetPropertyStr(ctx, clientObj, "chat",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let messages: [AIChatMessage]
            do {
                messages = try AIModule.parseMessages(ctx: ctx, value: argv[0])
            } catch {
                return error.localizedDescription.withCString { QJS_ThrowTypeError(ctx, $0) }
            }
            guard let call = AIModule.request(ctx, thisVal, argc, argv) else {
                return "Unknown AI provider".withCString { QJS_ThrowTypeError(ctx, $0) }
            }

            let (promise, settle) = JSBridge.deferred(ctx, dryRun: "")
            // deferred has already resolved the stub; do not go to the network.
            if Engine.isDryRun(ctx) { return promise }
            Task.detached {
                do {
                    let text = try await call.provider.chat(messages: messages, options: call.options)
                    await MainActor.run { settle(.value(text)) }
                } catch {
                    await MainActor.run { settle(.failure(error.localizedDescription)) }
                }
            }
            return promise
        }, "chat", 2))

        JS_SetPropertyStr(ctx, clientObj, "stream",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let messages: [AIChatMessage]
            do {
                messages = try AIModule.parseMessages(ctx: ctx, value: argv[0])
            } catch {
                return error.localizedDescription.withCString { QJS_ThrowTypeError(ctx, $0) }
            }
            guard let call = AIModule.request(ctx, thisVal, argc, argv) else {
                return "Unknown AI provider".withCString { QJS_ThrowTypeError(ctx, $0) }
            }

            var jsOnChunk: JSValue?
            if argc >= 2 {
                let onChunkVal = JSBridge.getProperty(ctx, argv[1], "onChunk")
                if JS_IsFunction(ctx, onChunkVal) {
                    jsOnChunk = JS_DupValue(ctx, onChunkVal)
                }
                JS_FreeValue(ctx, onChunkVal)
            }

            if Engine.isDryRun(ctx) {
                if let jsOnChunk { JS_FreeValue(ctx, jsOnChunk) }
                return JSBridge.deferred(ctx, dryRun: "").promise
            }
            // Not JSBridge.deferred: the chunk callback has to be freed if the
            // engine resets mid-stream, and only registerPending's `extras`
            // carries something to free alongside the promise pair.
            var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolving)
            let resolve = JS_DupValue(ctx, resolving[0])
            let reject = JS_DupValue(ctx, resolving[1])
            JS_FreeValue(ctx, resolving[0])
            JS_FreeValue(ctx, resolving[1])
            guard let engine = Engine.of(ctx) else {
                JS_FreeValue(ctx, resolve)
                JS_FreeValue(ctx, reject)
                if let jsOnChunk { JS_FreeValue(ctx, jsOnChunk) }
                return promise
            }
            let token = engine.registerPending(
                resolve: resolve,
                reject: reject,
                extras: jsOnChunk.map { [$0] } ?? []
            )
            nonisolated(unsafe) let capturedCtx = ctx
            let capturedOnChunk = jsOnChunk

            Task.detached {
                do {
                    let text = try await call.provider.stream(
                        messages: messages,
                        options: call.options,
                        onChunk: { chunk in
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    guard engine.isPending(token), let capturedOnChunk else { return }
                                    var arg = JSBridge.newString(capturedCtx, chunk)
                                    _ = JS_Call(capturedCtx, capturedOnChunk, QJS_Undefined(), 1, &arg)
                                    JS_FreeValue(capturedCtx, arg)
                                    engine.drainJobQueue()
                                }
                            }
                        }
                    )
                    await MainActor.run {
                        AIModule.settleStream(engine, capturedCtx, token, ok: true, text)
                    }
                } catch {
                    await MainActor.run {
                        AIModule.settleStream(
                            engine, capturedCtx, token, ok: false, error.localizedDescription
                        )
                    }
                }
            }
            return promise
        }, "stream", 2))

        return clientObj
    }

    /// Settle one stream promise and free everything it held: the capability
    /// pair and the chunk callback registered alongside it. Resolve and reject
    /// were the same eleven lines twice.
    @MainActor
    fileprivate static func settleStream(
        _ engine: Engine, _ ctx: OpaquePointer, _ token: UInt64, ok: Bool, _ text: String
    ) {
        guard let pending = engine.claimPending(token) else { return }
        var value = JSBridge.newString(ctx, text)
        _ = JS_Call(ctx, ok ? pending.resolve : pending.reject, QJS_Undefined(), 1, &value)
        JS_FreeValue(ctx, value)
        JS_FreeValue(ctx, pending.resolve)
        JS_FreeValue(ctx, pending.reject)
        for extra in pending.extras { JS_FreeValue(ctx, extra) }
        engine.drainJobQueue()
    }

    /// A client object from an optional `{ apiKey, model }` argument. The four
    /// provider factories differed only in the name they pass through here.
    private static func client(
        _ ctx: OpaquePointer, _ name: String, _ argc: Int32, _ argv: UnsafePointer<JSValue>?
    ) -> JSValue {
        var apiKey: String?
        var model: String?
        if let argv, argc >= 1, JS_IsObject(argv[0]) {
            apiKey = JSBridge.string(ctx, argv[0], "apiKey")
            model = JSBridge.string(ctx, argv[0], "model")
        }
        return createClientObject(ctx: ctx, providerName: name, apiKey: apiKey, model: model)
    }

    /// The provider stamped on the client object plus the per-request options
    /// from `argv[1]`. chat and stream read exactly the same seven fields.
    /// nil means the client names a provider that does not exist.
    private static func request(
        _ ctx: OpaquePointer, _ thisVal: JSValue, _ argc: Int32, _ argv: UnsafePointer<JSValue>?
    ) -> (provider: AIProvider, options: AIRequestOptions)? {
        let name = JSBridge.string(ctx, thisVal, "_provider") ?? "unknown"
        let apiKey = JSBridge.string(ctx, thisVal, "_apiKey")
        let storedModel = JSBridge.string(ctx, thisVal, "_model")
        guard let provider = provider(name, apiKey: apiKey, model: storedModel) else { return nil }

        var model = storedModel
        var maxTokens = 4096
        var temperature = 0.7
        var systemPrompt: String?
        if let argv, argc >= 2, JS_IsObject(argv[1]) {
            let opts = argv[1]
            model = JSBridge.string(ctx, opts, "model") ?? storedModel
            maxTokens = JSBridge.int(ctx, opts, "maxTokens") ?? maxTokens
            temperature = JSBridge.double(ctx, opts, "temperature") ?? temperature
            systemPrompt = JSBridge.string(ctx, opts, "system")
        }
        return (provider, AIRequestOptions(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            systemPrompt: systemPrompt
        ))
    }

    private static func parseMessages(ctx: OpaquePointer, value: JSValue) throws -> [AIChatMessage] {
        if JS_IsString(value) {
            let text = JSBridge.toString(ctx, value) ?? ""
            return try AIChatMessages.normalize([.user(text)])
        }
        let lengthVal = JSBridge.getProperty(ctx, value, "length")
        defer { JS_FreeValue(ctx, lengthVal) }
        guard !JSBridge.isUndefined(lengthVal) else {
            throw AIChatMessageError.emptyMessages
        }
        let length = Int(JSBridge.toInt32(ctx, lengthVal))
        var messages: [AIChatMessage] = []
        for i in 0..<length {
            let elem = JS_GetPropertyUint32(ctx, value, UInt32(i))
            defer { JS_FreeValue(ctx, elem) }
            let roleVal = JSBridge.getProperty(ctx, elem, "role")
            let contentVal = JSBridge.getProperty(ctx, elem, "content")
            defer {
                JS_FreeValue(ctx, roleVal)
                JS_FreeValue(ctx, contentVal)
            }
            let role = JSBridge.toString(ctx, roleVal) ?? ""
            let content = JSBridge.toString(ctx, contentVal) ?? ""
            messages.append(AIChatMessage(role: role, content: content))
        }
        return try AIChatMessages.normalize(messages)
    }

    private static func provider(_ name: String, apiKey: String?, model: String?) -> AIProvider? {
        switch name {
        case "claude": return ClaudeProvider(apiKey: apiKey, model: model)
        case "openai": return OpenAIProvider(apiKey: apiKey, model: model)
        case "gemini": return GeminiProvider(apiKey: apiKey, model: model)
        case "local": return LocalProvider()
        default: return nil
        }
    }
}
