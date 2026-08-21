import Foundation
import AI
import MacotronEngine

@main
enum PluginScanCLI {
    static func main() async {
        do {
            let args = try Args.parse(Array(CommandLine.arguments.dropFirst()))
            let passJobs = jobs(from: args.passPaths, expect: true)
            let failJobs = jobs(from: args.failPaths, expect: false)
            let all = passJobs + failJobs
            if all.isEmpty {
                fputs("no plugin files found\n", stderr)
                exit(1)
            }

            var records: [Record] = []
            records.reserveCapacity(all.count * args.runs)
            let writer = args.out.map { LineWriter($0) }

            await withTaskGroup(of: Record.self) { group in
                var i = 0
                var inflight = 0
                let pending = all.flatMap { job in (0..<args.runs).map { run in (job, run) } }
                while i < pending.count || inflight > 0 {
                    while inflight < args.concurrency, i < pending.count {
                        let (job, run) = pending[i]
                        i += 1
                        inflight += 1
                        group.addTask {
                            await scan(job: job, run: run)
                        }
                    }
                    if let record = await group.next() {
                        inflight -= 1
                        records.append(record)
                        writer?.write(record)
                        print(record.line, terminator: "")
                    }
                }
            }
            writer?.close()

            if let reason = records.first(where: { !$0.modelAvailable })?.unavailable {
                fputs("on-device model unavailable: \(reason)\n", stderr)
                exit(2)
            }

            let summary = Summary(records: records)
            print(summary.text)
            if !summary.ok { exit(1) }
        } catch {
            fputs("\(error)\n", stderr)
            exit(2)
        }
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
                        path: file.path,
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
        let correct = report.approved == job.expectPass
        return Record(
            name: job.name,
            expectPass: job.expectPass,
            run: run,
            approved: report.approved,
            modelAvailable: report.modelAvailable,
            unavailable: report.unavailableReason,
            findings: report.findings.map { "p\($0.pass): \($0.message)" },
            staticFlags: report.staticFlags,
            correct: correct,
            ms: Int(Date().timeIntervalSince(started) * 1000)
        )
    }
}

private struct Job: Sendable {
    var path: String
    var name: String
    var source: String
    var title: String
    var permissions: [String]
    var expectPass: Bool
}

private struct Record: Sendable {
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

    var json: [String: Any] {
        [
            "name": name,
            "expectPass": expectPass,
            "run": run,
            "approved": approved,
            "modelAvailable": modelAvailable,
            "unavailable": unavailable as Any,
            "findings": findings,
            "staticFlags": staticFlags,
            "correct": correct,
            "ms": ms,
        ]
    }
}

private struct Summary {
    var passTrials: Int
    var passHits: Int
    var failTrials: Int
    var failHits: Int

    var ok: Bool { passTrials == passHits && failTrials == failHits }

    init(records: [Record]) {
        let pass = records.filter(\.expectPass)
        let fail = records.filter { !$0.expectPass }
        passTrials = pass.count
        passHits = pass.filter(\.correct).count
        failTrials = fail.count
        failHits = fail.filter(\.correct).count
    }

    var text: String {
        func pct(_ hits: Int, _ total: Int) -> String {
            guard total > 0 else { return "n/a" }
            return String(format: "%.1f%%", 100.0 * Double(hits) / Double(total))
        }
        return """
        built-ins \(passHits)/\(passTrials) (\(pct(passHits, passTrials)))
        malware   \(failHits)/\(failTrials) (\(pct(failHits, failTrials)))
        """
    }
}

private struct Args {
    var runs: Int = 3
    var concurrency: Int = 16
    var out: String?
    var passPaths: [String] = []
    var failPaths: [String] = []

    static func parse(_ argv: [String]) throws -> Args {
        var args = Args()
        var i = 0
        var current: [String] = []
        func flush() {
            args.passPaths.append(contentsOf: current)
            current = []
        }
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--runs":
                i += 1
                args.runs = max(1, Int(argv[safe: i] ?? "") ?? 3)
            case "--concurrency":
                i += 1
                args.concurrency = max(1, Int(argv[safe: i] ?? "") ?? 16)
            case "--out":
                i += 1
                args.out = argv[safe: i]
            case "--fail":
                flush()
                i += 1
                if let path = argv[safe: i] { args.failPaths.append(path) }
            case "--help", "-h":
                print("""
                    PluginScan [--runs N] [--concurrency N] [--out FILE] DIR \
                    [--fail DIR]
                    """)
                exit(0)
            default:
                if a.hasPrefix("-") { throw CLIError("unknown flag \(a)") }
                current.append(a)
            }
            i += 1
        }
        flush()
        if args.passPaths.isEmpty { args.passPaths = ["Examples/plugins"] }
        if args.failPaths.isEmpty,
           FileManager.default.fileExists(atPath: "tmp/malware") {
            args.failPaths = ["tmp/malware"]
        }
        return args
    }
}

private final class LineWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    init(_ path: String) {
        FileManager.default.createFile(atPath: path, contents: Data())
        handle = try! FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }

    func write(_ record: Record) {
        guard JSONSerialization.isValidJSONObject(record.json),
              let data = try? JSONSerialization.data(withJSONObject: record.json) else { return }
        lock.lock()
        handle.write(data)
        handle.write(Data("\n".utf8))
        lock.unlock()
    }

    func close() {
        try? handle.close()
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct CLIError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
