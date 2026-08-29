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

    /// mdfind emits index order, which reads as random, so the cap keeps the
    /// most recently used rather than whichever the index named first.
    // ponytail: one stat per hit over the whole result set; NSMetadataQuery with
    // kMDItemLastUsedDate sorting (and live updates) if that ever costs too much.
    static func parse(_ stdout: String) -> [[String: Any]] {
        let urls: [URL] = stdout.split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
        let dated: [(url: URL, used: Date, order: Int)] = urls.enumerated().map { idx, url in
            let values = try? url.resourceValues(forKeys: [.contentAccessDateKey])
            return (url, values?.contentAccessDate ?? .distantPast, idx)
        }
        // Sorting is not stable, so untouched files keep mdfind's order.
        let ranked = dated.sorted { $0.used == $1.used ? $0.order < $1.order : $0.used > $1.used }
        return ranked.prefix(limit).map { row in
            [
                "path": row.url.path,
                "name": row.url.lastPathComponent,
                "kind": row.url.pathExtension,
            ]
        }
    }

    static func run(_ raw: String, folder: String?, kind: String?) -> [[String: Any]] {
        guard let query = queryString(raw, kind: kind) else { return [] }
        let dir = folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let args = dir.isEmpty ? [query] : ["-onlyin", (dir as NSString).expandingTildeInPath, query]
        return parse(Subprocess.run("/usr/bin/mdfind", args).stdout)
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

            let searchFolder = folder
            let searchKind = kind
            guard SpotlightSearch.queryString(queryString, kind: kind) != nil else {
                return JSBridge.promise(ctx, dryRun: [Any]()) { .value([Any]()) }
            }
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                .value(SpotlightSearch.run(queryString, folder: searchFolder, kind: searchKind)
                    .map { $0 as Any })
            }
        }, "search", 2))

        JS_SetPropertyStr(ctx, macotronObj, "spotlight", spotlightObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)
    }
}
