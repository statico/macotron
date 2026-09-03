// SearchProbe — run the launcher's file and app search from the command line.
//
//   swift run SearchProbe <query>          file search: the index when
//                                          macotron-index is built, else Spotlight
//   swift run SearchProbe --apps <query>   app-name matching with the same scorer
//
// A development probe: it prints what the launcher would show, with timing,
// so ranking changes can be checked against a real disk without the app.
import Foundation
import MacotronEngine
import Modules

var args = Array(CommandLine.arguments.dropFirst())
let apps = args.firstIndex(of: "--apps").map { args.remove(at: $0) } != nil
guard let query = args.first else {
    print("usage: SearchProbe [--apps] <query>")
    exit(1)
}

let start = Date()
if apps {
    let names = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        .flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { String($0.dropLast(4)) }
        }
    let ranked = FuzzyMatch.rank(names, query: query) { [$0] }
    for name in ranked.prefix(10) { print(name) }
} else if FileIndex.shared.available {
    // Cold start: the first search answers from a partial index while the
    // walk runs, so the timing line reports which case it measured.
    let index = FileIndex.shared
    // The same scopes and ignore list the plugin ships as its defaults.
    try index.configure(roots: ["~", "/Applications",
                                "~/Library/Mobile Documents/com~apple~CloudDocs",
                                "~/Library/CloudStorage"],
                        ignore: ["node_modules", "*.tmp", "go/pkg", "Library"],
                        hidden: false, ignoreFiles: true)
    // The probe starts its own indexer, so the walk runs first; the timing
    // line measures the search alone, the way the running app sees it.
    var status = try index.status()
    while status["indexing"] as? Bool == true {
        Thread.sleep(forTimeInterval: 0.1)
        status = try index.status()
    }
    print(String(format: "-- index: %@ entries, built in %.1f s",
                 "\(status["entries"] ?? 0)", Date().timeIntervalSince(start)))
    let searchStart = Date()
    let rows = try index.search(query: query, limit: 10)
    print(String(format: "-- search %.1f ms", Date().timeIntervalSince(searchStart) * 1000))
    for row in rows { print(row["path"] as? String ?? "?") }
} else {
    print("-- spotlight (no macotron-index; run make build)")
    for row in SpotlightSearch.run(query, folder: nil, kind: nil).prefix(10) {
        print(row["path"] as? String ?? "?")
    }
}
print(String(format: "-- %.0f ms", Date().timeIntervalSince(start) * 1000))
