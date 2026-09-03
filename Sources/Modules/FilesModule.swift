// FilesModule.swift — macotron.files: name search over the in-memory file index
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class FilesModule: NativeModule {
    public let name = "files"
    public let moduleVersion = 1

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let filesObj = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, filesObj, "configure",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            var opts: [String: Any] = [:]
            if argc >= 1, let argv, JS_IsObject(argv[0]) {
                opts = JSBridge.jsToSwift(ctx, argv[0]) as? [String: Any] ?? [:]
            }
            let roots = opts["roots"] as? [String] ?? ["~", "/Applications"]
            let ignore = opts["ignore"] as? [String] ?? []
            let hidden = opts["hidden"] as? Bool ?? false
            let ignoreFiles = opts["ignoreFiles"] as? Bool ?? true
            return JSBridge.promise(ctx) {
                FilesModule.void {
                    try FileIndex.shared.configure(
                        roots: roots, ignore: ignore, hidden: hidden, ignoreFiles: ignoreFiles)
                }
            }
        }, "configure", 1))

        JS_SetPropertyStr(ctx, filesObj, "search",
                          JS_NewCFunction(ctx, { ctx, _, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let query = JSBridge.toString(ctx, argv[0]) ?? ""
            var opts: [String: Any] = [:]
            if argc >= 2, JS_IsObject(argv[1]), !JS_IsString(argv[1]) {
                opts = JSBridge.jsToSwift(ctx, argv[1]) as? [String: Any] ?? [:]
            }
            let folder = opts["folder"] as? String
            let kind = opts["kind"] as? String
            let dirsOnly = opts["dirsOnly"] as? Bool ?? false
            let limit = (opts["limit"] as? NSNumber)?.intValue ?? 50
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                do {
                    let rows = try FileIndex.shared.search(
                        query: query, folder: folder, kind: kind, dirsOnly: dirsOnly, limit: limit)
                    return .value(rows.map { $0 as Any })
                } catch FileIndex.Failure.unavailable {
                    return .failure("file indexer unavailable")
                } catch {
                    return .failure("\(error)")
                }
            }
        }, "search", 2))

        JS_SetPropertyStr(ctx, filesObj, "status",
                          JS_NewCFunction(ctx, { ctx, _, _, _ -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: ["available": false]) {
                var status: [String: Any] = [
                    "entries": 0, "indexing": false, "watching": false, "roots": [String](),
                    "lastIndexed": 0, "memoryBytes": 0, "available": false,
                ]
                do {
                    for (key, value) in try FileIndex.shared.status() where key != "id" && key != "ok" {
                        status[key] = value
                    }
                    status["available"] = true
                } catch FileIndex.Failure.unavailable {
                } catch {
                    return .failure("\(error)")
                }
                return .value(status)
            }
        }, "status", 0))

        JS_SetPropertyStr(ctx, filesObj, "reindex",
                          JS_NewCFunction(ctx, { ctx, _, _, _ -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx) {
                FilesModule.void { try FileIndex.shared.reindex() }
            }
        }, "reindex", 0))

        JS_SetPropertyStr(ctx, macotronObj, "files", filesObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }

    /// A void call: an absent indexer is not an error, since the plugin falls
    /// back to Spotlight; anything the indexer itself refused is.
    nonisolated private static func void(_ work: () throws -> Void) -> BridgeResult {
        do {
            try work()
        } catch FileIndex.Failure.unavailable {
        } catch {
            return .failure("\(error)")
        }
        return .value(NSNull())
    }
}
