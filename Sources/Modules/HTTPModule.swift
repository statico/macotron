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

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let httpObj = JS_NewObject(ctx)

        // macotron.http.get(url, opts?) → Promise<{status, body, headers}>
        JS_SetPropertyStr(ctx, httpObj, "get",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "GET", argc: argc, argv: argv, hasBody: false)
        }, "get", 2))

        // macotron.http.post(url, body, opts?) → Promise<{status, body, headers}>
        JS_SetPropertyStr(ctx, httpObj, "post",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "POST", argc: argc, argv: argv, hasBody: true)
        }, "post", 3))

        // macotron.http.put(url, body, opts?) → Promise<{status, body, headers}>
        JS_SetPropertyStr(ctx, httpObj, "put",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "PUT", argc: argc, argv: argv, hasBody: true)
        }, "put", 3))

        // macotron.http.delete(url, opts?) → Promise<{status, body, headers}>
        JS_SetPropertyStr(ctx, httpObj, "delete",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "DELETE", argc: argc, argv: argv, hasBody: false)
        }, "delete", 2))

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

            // Extract headers from opts.headers
            let headersVal = JSBridge.getProperty(ctx, opts, "headers")
            if !JSBridge.isUndefined(headersVal) {
                // Enumerate header properties using JS_GetPropertyNames (if available)
                // For now, support common headers via known keys
                let commonHeaders = [
                    "Content-Type", "Authorization", "Accept",
                    "User-Agent", "X-API-Key", "X-Request-ID"
                ]
                for header in commonHeaders {
                    let val = JSBridge.getProperty(ctx, headersVal, header)
                    if !JSBridge.isUndefined(val), let str = JSBridge.toString(ctx, val) {
                        request.setValue(str, forHTTPHeaderField: header)
                    }
                    JS_FreeValue(ctx, val)
                }
            }
            JS_FreeValue(ctx, headersVal)

            // Extract timeout from opts.timeout
            let timeoutVal = JSBridge.getProperty(ctx, opts, "timeout")
            if !JSBridge.isUndefined(timeoutVal) {
                let timeoutMs = JSBridge.toDouble(ctx, timeoutVal)
                if timeoutMs > 0 {
                    request.timeoutInterval = timeoutMs / 1000.0
                }
            }
            JS_FreeValue(ctx, timeoutVal)
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
