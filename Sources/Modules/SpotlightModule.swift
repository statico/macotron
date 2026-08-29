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
        // A leading wildcard cannot seek the index, so it scans every term in it:
        // measured at 4.0s against 0.03s for the same search written as a prefix.
        // The `w` modifier keeps this matching mid-name words ("budget" still finds
        // "Q3 Budget.pdf"), `d` costs 4x for diacritic folding nobody asked for, and
        // kMDItemDisplayName is 3x kMDItemFSName for the same answer.
        var query = "kMDItemFSName == '\(e)*'cw"
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

    /// How obvious a hit is for what was typed. mdfind emits index order, which
    /// reads as random, so every hit is scored against these before the cut.
    ///
    /// Shortest path first is the whole idea: typing "downloads" should find
    /// ~/Downloads, not the fourth `downloads` folder inside a node_modules
    /// tree. Depth alone gets most of the way there, and the flags ahead of it
    /// cover what depth cannot see.
    struct Rank: Comparable {
        /// Each flag is 0 for the better answer, so the whole rank sorts ascending.
        let notExact: Int
        let hidden: Int
        let elsewhere: Int
        let depth: Int
        let path: String

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            (lhs.notExact, lhs.hidden, lhs.elsewhere, lhs.depth, lhs.path)
                < (rhs.notExact, rhs.hidden, rhs.elsewhere, rhs.depth, rhs.path)
        }
    }

    static func rank(path: String, term: String, home: String) -> Rank {
        let components = path.split(separator: "/")
        let name = String(components.last ?? "")
        return Rank(
            notExact: name.lowercased() == term.lowercased() ? 0 : 1,
            // A dot component means .git, .cache, .build: thousands of files
            // nobody opens by name, and always more of them than of the answer.
            hidden: components.contains { $0.hasPrefix(".") } ? 1 : 0,
            elsewhere: path.hasPrefix(home + "/") || path.hasPrefix("/Applications/")
                || path == home || path == "/Applications" ? 0 : 1,
            depth: components.count,
            path: path
        )
    }

    static func parse(_ stdout: String, term: String = "", home: String = NSHomeDirectory()) -> [[String: Any]] {
        let ranked = stdout.split(whereSeparator: \.isNewline)
            .map { line -> (path: String, rank: Rank) in
                let path = String(line)
                return (path, rank(path: path, term: term, home: home))
            }
            .sorted { $0.rank < $1.rank }
        return ranked.prefix(limit).map { row in
            let url = URL(fileURLWithPath: row.path)
            return [
                "path": row.path,
                "name": url.lastPathComponent,
                "kind": url.pathExtension,
            ]
        }
    }

    static func run(_ raw: String, folder: String?, kind: String?) -> [[String: Any]] {
        guard let query = queryString(raw, kind: kind) else { return [] }
        let dir = folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let args = dir.isEmpty ? [query] : ["-onlyin", (dir as NSString).expandingTildeInPath, query]
        return parse(Subprocess.run("/usr/bin/mdfind", args).stdout, term: raw.trimmingCharacters(in: .whitespacesAndNewlines))
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
