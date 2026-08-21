import CQuickJS
import Foundation
import MacotronEngine
import Vision

private enum OCRInput: Sendable {
    case data(Data)
    case path(String)
}

@MainActor
public final class OCRModule: NativeModule {
    public let name = "ocr"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let ocr = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, ocr, "recognize",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "ocr.recognize requires { path } or { image }")
            }

            let opts = argv[0]
            let pathValue = JSBridge.getProperty(ctx, opts, "path")
            let imageValue = JSBridge.getProperty(ctx, opts, "image")
            let path = JSBridge.isUndefined(pathValue) ? nil : JSBridge.toString(ctx, pathValue)
            let image = JSBridge.isUndefined(imageValue) ? nil : JSBridge.toString(ctx, imageValue)
            JS_FreeValue(ctx, pathValue)
            JS_FreeValue(ctx, imageValue)

            let input: OCRInput
            if let path, !path.isEmpty {
                input = .path((path as NSString).expandingTildeInPath)
            } else if let image, let data = OCRModule.decodeBase64(image) {
                input = .data(data)
            } else {
                return QJS_ThrowTypeError(ctx, "ocr.recognize requires a valid path or base64 image")
            }

            var resolving = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolving)
            let resolve = JS_DupValue(ctx, resolving[0])
            let reject = JS_DupValue(ctx, resolving[1])
            JS_FreeValue(ctx, resolving[0])
            JS_FreeValue(ctx, resolving[1])

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return promise }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
            let token = engine.registerPending(resolve: resolve, reject: reject)
            nonisolated(unsafe) let capturedCtx = ctx

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true

                    switch input {
                    case .data(let data):
                        try VNImageRequestHandler(data: data).perform([request])
                    case .path(let path):
                        try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([request])
                    }

                    let text = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")

                    DispatchQueue.main.async {
                        guard let pending = engine.claimPending(token) else { return }
                        var value = JSBridge.newString(capturedCtx, text)
                        _ = JS_Call(capturedCtx, pending.resolve, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, pending.resolve)
                        JS_FreeValue(capturedCtx, pending.reject)
                        engine.drainJobQueue()
                    }
                } catch {
                    DispatchQueue.main.async {
                        guard let pending = engine.claimPending(token) else { return }
                        var value = JSBridge.newString(capturedCtx, error.localizedDescription)
                        _ = JS_Call(capturedCtx, pending.reject, QJS_Undefined(), 1, &value)
                        JS_FreeValue(capturedCtx, value)
                        JS_FreeValue(capturedCtx, pending.resolve)
                        JS_FreeValue(capturedCtx, pending.reject)
                        engine.drainJobQueue()
                    }
                }
            }

            return promise
        }, "recognize", 1))

        JS_SetPropertyStr(ctx, macotron, "ocr", ocr)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    private static func decodeBase64(_ value: String) -> Data? {
        let encoded = value.hasPrefix("data:")
            ? value.split(separator: ",", maxSplits: 1).last.map(String.init) ?? ""
            : value
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }
}
