// SpotlightModule.swift — macotron.spotlight: Spotlight metadata search
import CQuickJS
import Foundation
import MacotronEngine

enum SpotlightSearch {
    static let limit = 50

    static func queryString(_ raw: String, kind: String? = nil) -> String? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let e = escape(q)
        var query = "(kMDItemDisplayName == '*\(e)*'cd || kMDItemFSName == '*\(e)*'cd)"
        var ext = kind?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while ext.hasPrefix(".") { ext.removeFirst() }
        if !ext.isEmpty {
            query += " && kMDItemFSName == '*.\(escape(ext))'cd"
        }
        return query
    }

    static func escape(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            if "\\*()'".contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    static func parse(_ stdout: String) -> [[String: Any]] {
        stdout.split(whereSeparator: \.isNewline).prefix(limit).compactMap { line in
            let path = String(line)
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            return [
                "path": path,
                "name": url.lastPathComponent,
                "kind": url.pathExtension,
            ]
        }
    }

    static func run(_ raw: String) -> [[String: Any]] {
        run(raw, folder: nil, kind: nil)
    }

    static func run(_ raw: String, folder: String?, kind: String?) -> [[String: Any]] {
        guard let query = queryString(raw, kind: kind) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        let dir = folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process.arguments = dir.isEmpty
            ? [query]
            : ["-onlyin", (dir as NSString).expandingTildeInPath, query]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return parse(String(data: data, encoding: .utf8) ?? "")
    }
}

@MainActor
public final class SpotlightModule: NativeModule {
    public let name = "spotlight"
    public let moduleVersion = 2

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let spotlightObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, spotlightObj, "search",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let queryString = JSBridge.toString(ctx, argv[0]) ?? ""
            var folder: String?
            var kind: String?
            if argc >= 2, JS_IsObject(argv[1]), !JS_IsString(argv[1]) {
                let opts = JSBridge.jsToSwift(ctx, argv[1]) as? [String: Any] ?? [:]
                folder = opts["folder"] as? String
                kind = opts["kind"] as? String
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
            nonisolated(unsafe) let capturedCtx = ctx

            if engine.dryRun || SpotlightSearch.queryString(queryString, kind: kind) == nil {
                var value = JSBridge.newArray(ctx, [])
                _ = JS_Call(ctx, resolve, QJS_Undefined(), 1, &value)
                JS_FreeValue(ctx, value)
                JS_FreeValue(ctx, resolve)
                JS_FreeValue(ctx, reject)
                engine.drainJobQueue()
                return promise
            }

            let searchFolder = folder
            let searchKind = kind
            DispatchQueue.global(qos: .userInitiated).async {
                let rows = SpotlightSearch.run(queryString, folder: searchFolder, kind: searchKind)
                DispatchQueue.main.async {
                    var value = JSBridge.newArray(capturedCtx, rows.map { $0 as Any })
                    _ = JS_Call(capturedCtx, resolve, QJS_Undefined(), 1, &value)
                    JS_FreeValue(capturedCtx, value)
                    JS_FreeValue(capturedCtx, resolve)
                    JS_FreeValue(capturedCtx, reject)
                    engine.drainJobQueue()
                }
            }
            return promise
        }, "search", 2))

        JS_SetPropertyStr(ctx, macotronObj, "spotlight", spotlightObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }
}
