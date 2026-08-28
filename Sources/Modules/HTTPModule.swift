// HTTPModule.swift — macotron.http: HTTP client (get/post/put/delete)
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "http")

@MainActor
public final class HTTPModule: NativeModule {
    public let name = "http"

    public init() {}

    /// One row per binding: the JS name, the HTTP method, and whether the
    /// second argument is a body or the options object.
    private static let methods: [(name: String, method: String, hasBody: Bool)] = [
        ("get", "GET", false),
        ("post", "POST", true),
        ("put", "PUT", true),
        ("delete", "DELETE", false),
    ]

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let httpObj = JS_NewObject(ctx)

        // get/delete take (url, opts?); post/put take (url, body, opts?). The
        // name, the HTTP method, and the body flag are one row, and the magic
        // index picks the row, so they cannot drift apart.
        for (index, entry) in HTTPModule.methods.enumerated() {
            JS_SetPropertyStr(ctx, httpObj, entry.name,
                              JS_NewCFunctionMagic(ctx, { ctx, _, argc, argv, magic -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                let entry = HTTPModule.methods[Int(magic)]
                return HTTPModule.performRequest(
                    ctx: ctx, method: entry.method, argc: argc, argv: argv, hasBody: entry.hasBody
                )
            }, entry.name, entry.hasBody ? 3 : 2, JS_CFUNC_generic_magic, Int32(index)))
        }

        JS_SetPropertyStr(ctx, macotron, "http", httpObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    // MARK: - Shared Request Implementation

    /// A failed request resolves with status 0 rather than rejecting: plugins
    /// already branch on the status code, so one check covers a 500 and a dead
    /// network alike.
    nonisolated private static func failed(_ message: String) -> [String: Any] {
        ["status": 0, "body": message, "headers": [String: Any]()]
    }

    /// Reads the arguments on the main thread — they are JS values, and the
    /// context is untouchable from the promise's queue — then hands the finished
    /// URLRequest to the network off-thread.
    @MainActor
    private static func performRequest(
        ctx: OpaquePointer,
        method: String,
        argc: Int32,
        argv: UnsafeMutablePointer<JSValue>,
        hasBody: Bool
    ) -> JSValue {
        let dry = failed("")
        guard let urlString = JSBridge.toString(ctx, argv[0]),
              let url = URL(string: urlString) else {
            logger.error("http.\(method.lowercased()): invalid URL")
            return JSBridge.promise(ctx, dryRun: dry) { .value(failed("Invalid URL")) }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        // Parse body for POST/PUT (second argument)
        if hasBody, argc >= 2 {
            if let bodyStr = JSBridge.toString(ctx, argv[1]) {
                request.httpBody = bodyStr.data(using: .utf8)
                // Default content type if not overridden by opts
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        // Parse opts (last argument, if it's an object)
        let optsIndex: Int32 = hasBody ? 2 : 1
        if argc > optsIndex {
            let opts = argv[Int(optsIndex)]

            // Only the headers a plugin is likely to set: QuickJS property
            // enumeration is not wired up here yet.
            let headersVal = JSBridge.getProperty(ctx, opts, "headers")
            for header in [
                "Content-Type", "Authorization", "Accept",
                "User-Agent", "X-API-Key", "X-Request-ID",
            ] {
                if let str = JSBridge.string(ctx, headersVal, header) {
                    request.setValue(str, forHTTPHeaderField: header)
                }
            }
            JS_FreeValue(ctx, headersVal)

            if let timeoutMs = JSBridge.double(ctx, opts, "timeout"), timeoutMs > 0 {
                request.timeoutInterval = timeoutMs / 1000.0
            }
        }

        let finished = request
        return JSBridge.promise(ctx, dryRun: dry) {
            send(finished, method: method, url: urlString)
        }
    }

    /// Blocks its queue on a semaphore. URLSession's async API is out of reach —
    /// the promise bridge hands out a synchronous closure — and the wait costs
    /// nothing now that it happens off the main thread.
    nonisolated private static func send(_ request: URLRequest, method: String, url: String) -> BridgeResult {
        nonisolated(unsafe) var responseData: Data?
        nonisolated(unsafe) var httpResponse: HTTPURLResponse?
        nonisolated(unsafe) var requestError: String?

        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                requestError = error.localizedDescription
            } else {
                responseData = data
                httpResponse = response as? HTTPURLResponse
            }
            semaphore.signal()
        }
        task.resume()

        // Belt and braces: URLSession enforces timeoutInterval itself, but a
        // wait that never returns would hold this queue's thread forever.
        if semaphore.wait(timeout: .now() + request.timeoutInterval + 5) == .timedOut {
            task.cancel()
            logger.error("http.\(method.lowercased()): request timed out for \(url)")
            return .value(failed("Request timed out"))
        }

        if let error = requestError {
            logger.error("http.\(method.lowercased()): \(error)")
            return .value(failed(error))
        }

        var headerDict: [String: Any] = [:]
        for (key, value) in httpResponse?.allHeaderFields ?? [:] {
            headerDict["\(key)"] = "\(value)"
        }
        return .value([
            "status": httpResponse?.statusCode ?? 0,
            "body": responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            "headers": headerDict,
        ] as [String: Any])
    }
}
