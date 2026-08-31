// SpotlightModule.swift — macotron.spotlight: Spotlight metadata search
import CQuickJS
import Foundation
import MacotronEngine

public enum SpotlightSearch {
    static let limit = 50

    static func row(_ path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        return ["path": path, "name": url.lastPathComponent, "kind": url.pathExtension]
    }

    static func children(_ dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir)) ?? []
    }

    /// A query with a slash is a path being typed, not a name. Each segment
    /// fuzzy-completes one directory level, so a couple of letters per level
    /// reach a deep folder without spelling any level out.
    public static func pathComplete(_ term: String, home: String = NSHomeDirectory()) -> [String] {
        guard term.contains("/") else { return [] }
        var rest = Substring(term)
        var frontier: [String]
        if rest.hasPrefix("~/") {
            frontier = [home]
            rest = rest.dropFirst(2)
        } else if rest.hasPrefix("/") {
            frontier = [""]
            rest = rest.dropFirst()
        } else {
            // "d/notes" means the same place as "~/d/notes", minus two keys.
            frontier = [home]
        }
        // From the original term: "~/" has already had its slash stripped.
        let listAll = term.hasSuffix("/")
        for segment in rest.split(separator: "/") {
            frontier = step(frontier, segment: String(segment))
            if frontier.isEmpty { return [] }
        }
        if listAll {
            frontier = frontier.flatMap { dir in
                children(dir).filter { !$0.hasPrefix(".") }.sorted().map { dir + "/" + $0 }
            }
        }
        return Array(frontier.prefix(limit))
    }

    /// One level of completion: every entry of every frontier directory that
    /// fuzzy-matches the segment, best score first. The cap keeps a vague
    /// early segment from exploding the walk; scoring puts prefixes ahead of
    /// scattered matches, so the folders someone means survive the cut.
    private static func step(_ dirs: [String], segment: String) -> [String] {
        let showHidden = segment.hasPrefix(".")
        var scored: [(path: String, score: Int)] = []
        for dir in dirs {
            for name in children(dir) {
                if !showHidden && name.hasPrefix(".") { continue }
                if let s = FuzzyMatch.score(query: segment, target: name) {
                    scored.append((dir + "/" + name, s))
                }
            }
        }
        return scored
            .sorted { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
            .prefix(32).map(\.path)
    }

    /// Visible folders a few levels under home, cached briefly. This is the
    /// candidate pool for fuzzy matches the index cannot express: mdfind only
    /// seeks by name prefix, so a query that jumps across path segments has to
    /// be matched here. node_modules and ~/Library are not descended into:
    /// they hold more folders than the rest of home combined and nobody
    /// reaches them by three fuzzy letters.
    nonisolated(unsafe) private static var walkCache: (home: String, paths: [String], stamp: Date)?

    static func folderWalk(home: String = NSHomeDirectory()) -> [String] {
        if let c = walkCache, c.home == home, Date().timeIntervalSince(c.stamp) < 60 {
            return c.paths
        }
        let fm = FileManager.default
        var out: [String] = []
        var level = [home]
        for _ in 0..<3 {
            var next: [String] = []
            for dir in level {
                for name in children(dir) where !name.hasPrefix(".") && !name.hasSuffix(".app") {
                    let path = dir + "/" + name
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
                    else { continue }
                    out.append(path)
                    if name != "node_modules" && path != home + "/Library" {
                        next.append(path)
                    }
                }
            }
            level = next
            // ponytail: hard cap instead of smarter pruning; revisit if a huge
            // home tree makes fuzzy results miss folders people actually want.
            if out.count > 20_000 { break }
        }
        walkCache = (home, out, Date())
        return out
    }

    /// Fuzzy folder hits for a query the prefix search cannot answer, best
    /// first. Scored against the path relative to home so the query can span
    /// segments: letters from a parent folder and its child match together.
    public static func fuzzy(_ term: String, home: String = NSHomeDirectory()) -> [String] {
        // Spaces separate ideas, not characters: "doc 3d" should match a
        // child folder of Documents even though no space sits on the way.
        let term = term.replacingOccurrences(of: " ", with: "")
        guard term.count >= 3, !term.contains("/") else { return [] }
        let prefixLen = home.count + 1
        var scored: [(path: String, score: Int)] = []
        for path in folderWalk(home: home) {
            let relative = String(path.dropFirst(prefixLen))
            if let s = FuzzyMatch.score(query: term, target: relative) {
                scored.append((path, s))
            }
        }
        scored.sort { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
        return scored.prefix(12).map(\.path)
    }

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
        let notPrefix: Int
        let hidden: Int
        let elsewhere: Int
        let depth: Int
        let path: String

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            (lhs.notExact, lhs.notPrefix, lhs.hidden, lhs.elsewhere, lhs.depth, lhs.path)
                < (rhs.notExact, rhs.notPrefix, rhs.hidden, rhs.elsewhere, rhs.depth, rhs.path)
        }
    }

    static func rank(path: String, term: String, home: String) -> Rank {
        let components = path.split(separator: "/")
        let name = String(components.last ?? "")
        return Rank(
            notExact: name.lowercased() == term.lowercased() ? 0 : 1,
            // Typing the start of a name is less ambiguous than hitting the
            // middle of one: "Desktop" over "Remote Desktop.app".
            notPrefix: name.lowercased().hasPrefix(term.lowercased()) ? 0 : 1,
            // A dot component means .git, .cache, .build: thousands of files
            // nobody opens by name, and always more of them than of the answer.
            hidden: components.contains { $0.hasPrefix(".") } ? 1 : 0,
            elsewhere: path.hasPrefix(home + "/") || path.hasPrefix("/Applications/")
                || path == home || path == "/Applications" ? 0 : 1,
            depth: components.count,
            path: path
        )
    }

    /// The roots Spotlight is blind to, plus the one everybody types.
    static func defaultRoots(home: String = NSHomeDirectory()) -> [String] {
        ["/", "/Applications", home]
    }

    /// Spotlight never returns the top level of a home directory: no query finds
    /// ~/Desktop or ~/dev, only things underneath them. Those are exactly the
    /// folders someone types three letters of, so the handful of roots that
    /// matter are read directly — a few dozen names, no index involved.
    static func shallow(_ term: String, roots: [String]) -> [String] {
        let t = term.lowercased()
        guard !t.isEmpty else { return [] }
        return roots.flatMap { root -> [String] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            return names
                .filter { name in
                    !name.hasPrefix(".") && name.lowercased()
                        .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
                        .contains { $0.hasPrefix(t) }
                }
                .map { root == "/" ? "/" + $0 : root + "/" + $0 }
        }
    }

    static func parse(
        _ stdout: String,
        extra: [String] = [],
        term: String = "",
        home: String = NSHomeDirectory()
    ) -> [[String: Any]] {
        var seen = Set<String>()
        let ranked = (extra + stdout.split(whereSeparator: \.isNewline).map(String.init))
            .filter { seen.insert($0).inserted }
            .map { path in (path: path, rank: rank(path: path, term: term, home: home)) }
            .sorted { $0.rank < $1.rank }
        return ranked.prefix(limit).map { row($0.path) }
    }

    public static func run(_ raw: String, folder: String?, kind: String?) -> [[String: Any]] {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = kind.map { "." + $0.drop(while: { $0 == "." }).lowercased() } ?? "."
        if term.contains("/") {
            var paths = pathComplete(term)
            if ext != "." {
                paths = paths.filter { $0.lowercased().hasSuffix(ext) }
            }
            return paths.map(row)
        }
        guard let query = queryString(raw, kind: kind) else { return [] }
        let dir = folder?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let root = (dir as NSString).expandingTildeInPath
        let args = dir.isEmpty ? [query] : ["-onlyin", root, query]
        var extra = shallow(term, roots: dir.isEmpty ? defaultRoots() : [root])
        if ext != "." {
            extra = extra.filter { $0.lowercased().hasSuffix(ext) }
        }
        var rows = parse(Subprocess.run("/usr/bin/mdfind", args).stdout, extra: extra, term: term)
        // Fuzzy hits go below every prefix hit: only a query the index cannot
        // answer at all surfaces them at the top. Folders carry no extension,
        // so a kind filter rules them out wholesale.
        if ext == "." && dir.isEmpty {
            let have = Set(rows.compactMap { $0["path"] as? String })
            rows += fuzzy(term).filter { !have.contains($0) }.map(row)
        }
        return Array(rows.prefix(limit))
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
