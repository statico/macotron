// HTTPModule.swift — macotron.http: synchronous HTTP client (get/post/put/delete)
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "http")

@MainActor
public final class HTTPModule: NativeModule {
    public let name = "http"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let httpObj = JS_NewObject(ctx)

        // macotron.http.get(url, opts?) → {status, body, headers}
        JS_SetPropertyStr(ctx, httpObj, "get",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "GET", argc: argc, argv: argv, hasBody: false)
        }, "get", 2))

        // macotron.http.post(url, body, opts?) → {status, body, headers}
        JS_SetPropertyStr(ctx, httpObj, "post",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "POST", argc: argc, argv: argv, hasBody: true)
        }, "post", 3))

        // macotron.http.put(url, body, opts?) → {status, body, headers}
        JS_SetPropertyStr(ctx, httpObj, "put",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            return HTTPModule.performRequest(ctx: ctx, method: "PUT", argc: argc, argv: argv, hasBody: true)
        }, "put", 3))

        // macotron.http.delete(url, opts?) → {status, body, headers}
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

    /// Perform a synchronous HTTP request using a semaphore.
    /// This blocks the calling thread until the response arrives or timeout.
    @MainActor
    private static func performRequest(
        ctx: OpaquePointer,
        method: String,
        argc: Int32,
        argv: UnsafeMutablePointer<JSValue>,
        hasBody: Bool
    ) -> JSValue {
        // Parse URL (always first argument)
        guard let urlString = JSBridge.toString(ctx, argv[0]),
              let url = URL(string: urlString) else {
            logger.error("http.\(method.lowercased()): invalid URL")
            return JSBridge.newObject(ctx, [
                "status": 0,
                "body": "Invalid URL",
                "headers": [String: Any]()
            ])
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

        // Perform synchronous request
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        var requestError: String?

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

        // Wait with timeout
        let timeoutSeconds = request.timeoutInterval + 5
        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)

        if waitResult == .timedOut {
            task.cancel()
            logger.error("http.\(method.lowercased()): request timed out for \(urlString)")
            return JSBridge.newObject(ctx, [
                "status": 0,
                "body": "Request timed out",
                "headers": [String: Any]()
            ])
        }

        if let error = requestError {
            logger.error("http.\(method.lowercased()): \(error)")
            return JSBridge.newObject(ctx, [
                "status": 0,
                "body": error,
                "headers": [String: Any]()
            ])
        }

        let statusCode = httpResponse?.statusCode ?? 0
        let bodyString = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // Convert response headers to a dict
        var headerDict: [String: Any] = [:]
        if let allHeaders = httpResponse?.allHeaderFields {
            for (key, value) in allHeaders {
                headerDict["\(key)"] = "\(value)"
            }
        }

        let result = JS_NewObject(ctx)
        JS_SetPropertyStr(ctx, result, "status", JSBridge.newInt32(ctx, Int32(statusCode)))
        JS_SetPropertyStr(ctx, result, "body", JSBridge.newString(ctx, bodyString))
        JS_SetPropertyStr(ctx, result, "headers", JSBridge.newObject(ctx, headerDict))
        return result
    }
}
