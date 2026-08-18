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
        JS_SetPropertyStr(ctx, aiObj, "claude",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            // Extract API key and model from opts
            var apiKey: String?
            var model: String?

            if let argv, argc >= 1 {
                let opts = argv[0]
                let keyVal = JSBridge.getProperty(ctx, opts, "apiKey")
                if !JSBridge.isUndefined(keyVal) {
                    apiKey = JSBridge.toString(ctx, keyVal)
                }
                JS_FreeValue(ctx, keyVal)

                let modelVal = JSBridge.getProperty(ctx, opts, "model")
                if !JSBridge.isUndefined(modelVal) {
                    model = JSBridge.toString(ctx, modelVal)
                }
                JS_FreeValue(ctx, modelVal)
            }

            return AIModule.createClientObject(
                ctx: ctx,
                providerName: "claude",
                apiKey: apiKey,
                model: model
            )
        }, "claude", 1))

        // macotron.ai.openai(opts?) → AI client object
        JS_SetPropertyStr(ctx, aiObj, "openai",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var apiKey: String?
            var model: String?

            if let argv, argc >= 1 {
                let opts = argv[0]
                let keyVal = JSBridge.getProperty(ctx, opts, "apiKey")
                if !JSBridge.isUndefined(keyVal) {
                    apiKey = JSBridge.toString(ctx, keyVal)
                }
                JS_FreeValue(ctx, keyVal)

                let modelVal = JSBridge.getProperty(ctx, opts, "model")
                if !JSBridge.isUndefined(modelVal) {
                    model = JSBridge.toString(ctx, modelVal)
                }
                JS_FreeValue(ctx, modelVal)
            }

            return AIModule.createClientObject(
                ctx: ctx,
                providerName: "openai",
                apiKey: apiKey,
                model: model
            )
        }, "openai", 1))

        // macotron.ai.gemini(opts?) → AI client object
        JS_SetPropertyStr(ctx, aiObj, "gemini",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var apiKey: String?
            var model: String?

            if let argv, argc >= 1 {
                let opts = argv[0]
                let keyVal = JSBridge.getProperty(ctx, opts, "apiKey")
                if !JSBridge.isUndefined(keyVal) {
                    apiKey = JSBridge.toString(ctx, keyVal)
                }
                JS_FreeValue(ctx, keyVal)

                let modelVal = JSBridge.getProperty(ctx, opts, "model")
                if !JSBridge.isUndefined(modelVal) {
                    model = JSBridge.toString(ctx, modelVal)
                }
                JS_FreeValue(ctx, modelVal)
            }

            return AIModule.createClientObject(
                ctx: ctx,
                providerName: "gemini",
                apiKey: apiKey,
                model: model
            )
        }, "gemini", 1))

        // macotron.ai.local() → AI client object
        JS_SetPropertyStr(ctx, aiObj, "local",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return AIModule.createClientObject(
                ctx: ctx,
                providerName: "local",
                apiKey: nil,
                model: nil
            )
        }, "local", 0))

        JS_SetPropertyStr(ctx, macotron, "ai", aiObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    // MARK: - Client Object Builder

    /// Create a JS object with .chat and .stream methods.
    @MainActor
    private static func createClientObject(
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

            let providerVal = JSBridge.getProperty(ctx, thisVal, "_provider")
            let providerName = JSBridge.toString(ctx, providerVal) ?? "unknown"
            JS_FreeValue(ctx, providerVal)

            let apiKeyVal = JSBridge.getProperty(ctx, thisVal, "_apiKey")
            let apiKey = JSBridge.toString(ctx, apiKeyVal)
            JS_FreeValue(ctx, apiKeyVal)

            let modelVal = JSBridge.getProperty(ctx, thisVal, "_model")
            let storedModel = JSBridge.toString(ctx, modelVal)
            JS_FreeValue(ctx, modelVal)

            var requestModel = storedModel
            var maxTokens = 4096
            var temperature = 0.7
            var systemPrompt: String?

            if argc >= 2 {
                let opts = argv[1]
                let mVal = JSBridge.getProperty(ctx, opts, "model")
                if !JSBridge.isUndefined(mVal), let m = JSBridge.toString(ctx, mVal) {
                    requestModel = m
                }
                JS_FreeValue(ctx, mVal)

                let mtVal = JSBridge.getProperty(ctx, opts, "maxTokens")
                if !JSBridge.isUndefined(mtVal) {
                    maxTokens = Int(JSBridge.toInt32(ctx, mtVal))
                }
                JS_FreeValue(ctx, mtVal)

                let tVal = JSBridge.getProperty(ctx, opts, "temperature")
                if !JSBridge.isUndefined(tVal) {
                    temperature = JSBridge.toDouble(ctx, tVal)
                }
                JS_FreeValue(ctx, tVal)

                let sVal = JSBridge.getProperty(ctx, opts, "system")
                if !JSBridge.isUndefined(sVal) {
                    systemPrompt = JSBridge.toString(ctx, sVal)
                }
                JS_FreeValue(ctx, sVal)
            }

            let options = AIRequestOptions(
                model: requestModel,
                maxTokens: maxTokens,
                temperature: temperature,
                systemPrompt: systemPrompt
            )

            let config = AIProviderFactory.ProviderConfig(apiKey: apiKey, model: storedModel)
            let provider = AIProviderFactory.create(name: providerName, config: config)

            var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolving)
            let resolve = JS_DupValue(ctx, resolving[0])
            let reject = JS_DupValue(ctx, resolving[1])
            JS_FreeValue(ctx, resolving[0])
            JS_FreeValue(ctx, resolving[1])

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return promise }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            nonisolated(unsafe) let capturedCtx = ctx

            Task.detached {
                do {
                    let text = try await provider.chat(messages: messages, options: options)
                    DispatchQueue.main.async {
                        var value = JSBridge.newString(capturedCtx, text)
                        _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                        engine.drainJobQueue()
                    }
                } catch {
                    DispatchQueue.main.async {
                        var value = JSBridge.newString(capturedCtx, error.localizedDescription)
                        _ = JS_Call(capturedCtx, reject, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                        engine.drainJobQueue()
                    }
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

            let providerVal = JSBridge.getProperty(ctx, thisVal, "_provider")
            let providerName = JSBridge.toString(ctx, providerVal) ?? "unknown"
            JS_FreeValue(ctx, providerVal)

            let apiKeyVal = JSBridge.getProperty(ctx, thisVal, "_apiKey")
            let apiKey = JSBridge.toString(ctx, apiKeyVal)
            JS_FreeValue(ctx, apiKeyVal)

            let modelVal = JSBridge.getProperty(ctx, thisVal, "_model")
            let storedModel = JSBridge.toString(ctx, modelVal)
            JS_FreeValue(ctx, modelVal)

            var requestModel = storedModel
            var maxTokens = 4096
            var temperature = 0.7
            var systemPrompt: String?
            var jsOnChunk: JSValue? = nil

            if argc >= 2 {
                let opts = argv[1]
                let mVal = JSBridge.getProperty(ctx, opts, "model")
                if !JSBridge.isUndefined(mVal), let m = JSBridge.toString(ctx, mVal) {
                    requestModel = m
                }
                JS_FreeValue(ctx, mVal)

                let mtVal = JSBridge.getProperty(ctx, opts, "maxTokens")
                if !JSBridge.isUndefined(mtVal) {
                    maxTokens = Int(JSBridge.toInt32(ctx, mtVal))
                }
                JS_FreeValue(ctx, mtVal)

                let tVal = JSBridge.getProperty(ctx, opts, "temperature")
                if !JSBridge.isUndefined(tVal) {
                    temperature = JSBridge.toDouble(ctx, tVal)
                }
                JS_FreeValue(ctx, tVal)

                let sVal = JSBridge.getProperty(ctx, opts, "system")
                if !JSBridge.isUndefined(sVal) {
                    systemPrompt = JSBridge.toString(ctx, sVal)
                }
                JS_FreeValue(ctx, sVal)

                let onChunkVal = JSBridge.getProperty(ctx, opts, "onChunk")
                if JS_IsFunction(ctx, onChunkVal) {
                    jsOnChunk = JS_DupValue(ctx, onChunkVal)
                }
                JS_FreeValue(ctx, onChunkVal)
            }

            let options = AIRequestOptions(
                model: requestModel,
                maxTokens: maxTokens,
                temperature: temperature,
                systemPrompt: systemPrompt
            )

            let config = AIProviderFactory.ProviderConfig(apiKey: apiKey, model: storedModel)
            let provider = AIProviderFactory.create(name: providerName, config: config)

            var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolving)
            let resolve = JS_DupValue(ctx, resolving[0])
            let reject = JS_DupValue(ctx, resolving[1])
            JS_FreeValue(ctx, resolving[0])
            JS_FreeValue(ctx, resolving[1])

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return promise }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            nonisolated(unsafe) let capturedCtx = ctx
            let capturedOnChunk = jsOnChunk

            Task.detached {
                do {
                    let text = try await provider.stream(
                        messages: messages,
                        options: options,
                        onChunk: { chunk in
                            DispatchQueue.main.async {
                                guard let ctx = engine.context, let capturedOnChunk else { return }
                                var arg = JSBridge.newString(ctx, chunk)
                                _ = JS_Call(ctx, capturedOnChunk, QJS_Undefined(), 1, &arg)
                                JS_FreeValue(ctx, arg)
                                engine.drainJobQueue()
                            }
                        }
                    )
                    DispatchQueue.main.async {
                        var value = JSBridge.newString(capturedCtx, text)
                        _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                        if let capturedOnChunk {
                            JS_FreeValue(capturedCtx, capturedOnChunk)
                        }
                        engine.drainJobQueue()
                    }
                } catch {
                    DispatchQueue.main.async {
                        var value = JSBridge.newString(capturedCtx, error.localizedDescription)
                        _ = JS_Call(capturedCtx, reject, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, resolve)
                        JS_FreeValue(capturedCtx, reject)
                        if let capturedOnChunk {
                            JS_FreeValue(capturedCtx, capturedOnChunk)
                        }
                        engine.drainJobQueue()
                    }
                }
            }

            return promise
        }, "stream", 2))

        return clientObj
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
}
