// AIModule.swift — macotron.ai: AI provider namespace with chat/stream methods
import AI
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai")

/// Thread-safe box for passing results between Task.detached and the caller
private final class ResultBox: @unchecked Sendable {
    var result: String?
    var error: String?
}

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

    /// Create a JS object with .chat(prompt, opts) and .stream(prompt, opts) methods.
    /// These methods perform synchronous HTTP calls via a semaphore (temporary approach).
    @MainActor
    private static func createClientObject(
        ctx: OpaquePointer,
        providerName: String,
        apiKey: String?,
        model: String?
    ) -> JSValue {
        let clientObj = JS_NewObject(ctx)

        // Store provider info as properties on the object
        JS_SetPropertyStr(ctx, clientObj, "_provider", JSBridge.newString(ctx, providerName))
        if let apiKey {
            JS_SetPropertyStr(ctx, clientObj, "_apiKey", JSBridge.newString(ctx, apiKey))
        }
        if let model {
            JS_SetPropertyStr(ctx, clientObj, "_model", JSBridge.newString(ctx, model))
        }

        // .chat(prompt, opts?) → string
        JS_SetPropertyStr(ctx, clientObj, "chat",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            let prompt = JSBridge.toString(ctx, argv[0]) ?? ""

            // Read provider config from `this`
            let providerVal = JSBridge.getProperty(ctx, thisVal, "_provider")
            let providerName = JSBridge.toString(ctx, providerVal) ?? "unknown"
            JS_FreeValue(ctx, providerVal)

            let apiKeyVal = JSBridge.getProperty(ctx, thisVal, "_apiKey")
            let apiKey = JSBridge.toString(ctx, apiKeyVal)
            JS_FreeValue(ctx, apiKeyVal)

            let modelVal = JSBridge.getProperty(ctx, thisVal, "_model")
            let storedModel = JSBridge.toString(ctx, modelVal)
            JS_FreeValue(ctx, modelVal)

            // Parse optional opts from second argument
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

            // Create the provider and call synchronously via semaphore
            let config = AIProviderFactory.ProviderConfig(apiKey: apiKey, model: storedModel)
            let provider = AIProviderFactory.create(name: providerName, config: config)

            let box = ResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            Task.detached {
                do {
                    box.result = try await provider.chat(prompt: prompt, options: options)
                } catch {
                    box.error = error.localizedDescription
                }
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + 120)
            if waitResult == .timedOut {
                logger.error("AI chat timed out for provider \(providerName)")
                return JSBridge.newString(ctx, "Error: request timed out")
            }

            if let error = box.error {
                logger.error("AI chat error: \(error)")
                return JSBridge.newString(ctx, "Error: \(error)")
            }

            return JSBridge.newString(ctx, box.result ?? "")
        }, "chat", 2))

        // .stream(prompt, opts?) → string (full response; streaming happens internally)
        JS_SetPropertyStr(ctx, clientObj, "stream",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            let prompt = JSBridge.toString(ctx, argv[0]) ?? ""

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

            let box = ResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            Task.detached {
                do {
                    box.result = try await provider.stream(
                        prompt: prompt,
                        options: options,
                        onChunk: { chunk in
                            logger.debug("Stream chunk: \(chunk.prefix(50))")
                        }
                    )
                } catch {
                    box.error = error.localizedDescription
                }
                semaphore.signal()
            }

            let waitResult = semaphore.wait(timeout: .now() + 120)
            if waitResult == .timedOut {
                logger.error("AI stream timed out for provider \(providerName)")
                return JSBridge.newString(ctx, "Error: request timed out")
            }

            if let error = box.error {
                logger.error("AI stream error: \(error)")
                return JSBridge.newString(ctx, "Error: \(error)")
            }

            return JSBridge.newString(ctx, box.result ?? "")
        }, "stream", 2))

        return clientObj
    }
}
