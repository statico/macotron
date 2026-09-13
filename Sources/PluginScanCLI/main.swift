import Foundation
import AI
import MacotronEngine

private let usage = "PluginScan [--runs N] [--concurrency N] [--out FILE] DIR [--fail DIR]"

@main
enum PluginScanCLI {
    static func main() async {
        var runs = 3
        var concurrency = 16
        var out: String?
        var passPaths: [String] = []
        var failPaths: [String] = []

        let argv = Array(CommandLine.arguments.dropFirst())
        var i = 0
        // Reads the argument after the current flag and steps past it.
        func value() -> String? {
            defer { i += 1 }
            return i < argv.count ? argv[i] : nil
        }
        while i < argv.count {
            let flag = argv[i]
            i += 1
            switch flag {
            case "--runs": runs = max(1, Int(value() ?? "") ?? 3)
            case "--concurrency": concurrency = max(1, Int(value() ?? "") ?? 16)
            case "--out": out = value()
            case "--fail": if let path = value() { failPaths.append(path) }
            case "--help", "-h": print(usage); exit(0)
            default:
                if flag.hasPrefix("-") {
                    fputs("unknown flag \(flag)\n\(usage)\n", stderr)
                    exit(2)
                }
                passPaths.append(flag)
            }
        }

        let all = jobs(from: passPaths, expect: true) + jobs(from: failPaths, expect: false)
        if all.isEmpty {
            fputs("no plugin files found\n", stderr)
            exit(1)
        }

        var records: [Record] = []
        await withTaskGroup(of: Record.self) { group in
            let pending = all.flatMap { job in (0..<runs).map { (job, $0) } }
            var next = 0
            var inflight = 0
            while next < pending.count || inflight > 0 {
                while inflight < concurrency, next < pending.count {
                    let (job, run) = pending[next]
                    next += 1
                    inflight += 1
                    group.addTask { await scan(job: job, run: run) }
                }
                if let record = await group.next() {
                    inflight -= 1
                    records.append(record)
                    print(record.line, terminator: "")
                }
            }
        }

        if let out {
            let encoder = JSONEncoder()
            let lines = records.compactMap { try? String(decoding: encoder.encode($0), as: UTF8.self) }
            try? (lines.joined(separator: "\n") + "\n")
                .write(toFile: out, atomically: true, encoding: .utf8)
        }

        if let reason = records.first(where: { !$0.modelAvailable })?.unavailable {
            fputs("on-device model unavailable: \(reason)\n", stderr)
            exit(2)
        }

        func tally(_ label: String, _ rows: [Record]) -> String {
            let hits = rows.filter(\.correct).count
            let pct = rows.isEmpty
                ? "n/a" : String(format: "%.1f%%", 100 * Double(hits) / Double(rows.count))
            return "\(label) \(hits)/\(rows.count) (\(pct))"
        }
        print(tally("built-ins", records.filter(\.expectPass)))
        print(tally("malware  ", records.filter { !$0.expectPass }))
        if records.contains(where: { !$0.correct }) { exit(1) }
    }

    private static func jobs(from paths: [String], expect: Bool) -> [Job] {
        paths.flatMap { path -> [Job] in
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
            let files: [URL]
            if isDir.boolValue {
                files = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil
                )) ?? []
            } else {
                files = [url]
            }
            return files
                .filter { $0.pathExtension == "js" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { file in
                    guard let source = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                    let header = PluginHeader.parse(source)
                    return Job(
                        name: file.lastPathComponent,
                        source: source,
                        title: header.title ?? file.deletingPathExtension().lastPathComponent,
                        permissions: header.permissions,
                        expectPass: expect
                    )
                }
        }
    }

    private static func scan(job: Job, run: Int) async -> Record {
        let started = Date()
        let report = await PluginScanner.scan(
            source: job.source,
            title: job.title,
            permissions: job.permissions
        )
        return Record(
            name: job.name,
            expectPass: job.expectPass,
            run: run,
            approved: report.approved,
            modelAvailable: report.modelAvailable,
            unavailable: report.unavailableReason,
            findings: report.findings.map { "p\($0.pass): \($0.message)" },
            staticFlags: report.staticFlags,
            correct: report.approved == job.expectPass,
            ms: Int(Date().timeIntervalSince(started) * 1000)
        )
    }
}

private struct Job: Sendable {
    var name: String
    var source: String
    var title: String
    var permissions: [String]
    var expectPass: Bool
}

private struct Record: Sendable, Encodable {
    var name: String
    var expectPass: Bool
    var run: Int
    var approved: Bool
    var modelAvailable: Bool
    var unavailable: String?
    var findings: [String]
    var staticFlags: [String]
    var correct: Bool
    var ms: Int

    var line: String {
        let mark = correct ? "ok" : "MISS"
        let extra = (staticFlags + findings).joined(separator: " | ")
        return "\(mark)  \(name)  run=\(run)  approved=\(approved)  \(extra)\n"
    }
}
