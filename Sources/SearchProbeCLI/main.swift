// SearchProbe — run the launcher's file and app search from the command line.
//
//   swift run SearchProbe <query>          file search, exactly what the host runs
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
} else {
    for row in SpotlightSearch.run(query, folder: nil, kind: nil).prefix(10) {
        print(row["path"] as? String ?? "?")
    }
}
print(String(format: "-- %.0f ms", Date().timeIntervalSince(start) * 1000))
