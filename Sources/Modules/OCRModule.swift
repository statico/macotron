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

            let path = JSBridge.string(ctx, argv[0], "path")
            let image = JSBridge.string(ctx, argv[0], "image")

            let input: OCRInput
            if let path, !path.isEmpty {
                input = .path((path as NSString).expandingTildeInPath)
            } else if let image, let data = OCRModule.decodeBase64(image) {
                input = .data(data)
            } else {
                return QJS_ThrowTypeError(ctx, "ocr.recognize requires a valid path or base64 image")
            }

            return JSBridge.promise(ctx, dryRun: "") {
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

                    return .value((request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n"))
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
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
