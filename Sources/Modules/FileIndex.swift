// FileIndex.swift — client for the macotron-index process (docs/12-file-index.md)
//
// One child process, spawned on the first request, spoken to over NDJSON on
// stdin/stdout. Requests block the calling thread until the matching response
// arrives; callers already sit inside a JSBridge.promise work closure on a
// global queue, so nothing here ever runs on main. stdout is drained by its
// own thread from the moment the child starts, which is what keeps a chatty
// child from filling the 64K pipe and stalling (see Subprocess.swift).
import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "files")

public final class FileIndex: @unchecked Sendable {
    public static let shared = FileIndex()

    public enum Failure: Error, CustomStringConvertible {
        /// No binary, or it died twice: callers fall back to Spotlight.
        case unavailable
        case error(String)

        public var description: String {
            switch self {
            case .unavailable: return "file indexer is not available"
            case .error(let message): return message
            }
        }
    }

    public static let timeout: TimeInterval = 10

    /// Where the binary lives: the env var, then next to the app executable
    /// (`make bundle` puts it there), then a local cargo build for
    /// `swift run`, tests and SearchProbe.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableDir: URL? = Bundle.main.executableURL?.deletingLastPathComponent(),
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> String? {
        var candidates: [String] = []
        if let env = environment["MACOTRON_INDEXER"], !env.isEmpty { candidates.append(env) }
        if let dir = executableDir { candidates.append(dir.appendingPathComponent("macotron-index").path) }
        candidates.append(cwd + "/Indexer/target/release/macotron-index")
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public let binary: String?
    public var available: Bool { binary != nil }

    /// One blocked caller waiting for the response with its id.
    final class Waiter: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        var response: [String: Any]?

        func wait(_ timeout: TimeInterval = FileIndex.timeout) {
            _ = semaphore.wait(timeout: .now() + timeout)
        }
    }

    private let lock = NSLock()
    /// Serialises stdin writes without holding `lock` across a pipe write,
    /// which can block when the child is not reading.
    private let writeLock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var waiters: [Int: Waiter] = [:]
    private var lastConfigure: [String: Any]?
    private var exits = 0
    private var shuttingDown = false
    private var observing = false

    public init(binary: String? = FileIndex.locate()) {
        self.binary = binary
    }

    // MARK: - Requests

    @discardableResult
    public func configure(
        roots: [String], ignore: [String], hidden: Bool, ignoreFiles: Bool
    ) throws -> [String: Any] {
        let body: [String: Any] = [
            "op": "configure",
            "roots": roots.map { ($0 as NSString).expandingTildeInPath },
            "ignore": ignore, "hidden": hidden, "ignoreFiles": ignoreFiles,
        ]
        lock.withLock { lastConfigure = body }
        return try request(body)
    }

    public func search(
        query: String, folder: String? = nil, kind: String? = nil,
        dirsOnly: Bool = false, limit: Int = 50
    ) throws -> [[String: Any]] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var body: [String: Any] = ["op": "search", "query": query, "limit": limit, "dirsOnly": dirsOnly]
        if let folder, !folder.isEmpty { body["folder"] = (folder as NSString).expandingTildeInPath }
        let ext = kind.map { String($0.drop(while: { $0 == "." })) } ?? ""
        if !ext.isEmpty { body["kind"] = ext }
        return try request(body)["results"] as? [[String: Any]] ?? []
    }

    public func status() throws -> [String: Any] {
        try request(["op": "status"])
    }

    public func reindex() throws {
        _ = try request(["op": "reindex"])
    }

    /// Ask the child to exit and stop talking to it. Called on app termination;
    /// the child also exits on its own when stdin closes with the app.
    public func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        shuttingDown = true
        guard let stdin else { return }
        let id = nextID
        nextID += 1
        self.stdin = nil
        writeLock.withLock {
            write(["id": id, "op": "shutdown"], to: stdin)
            try? stdin.close()
        }
    }

    /// Send one request and block for its response. Throws when the indexer is
    /// missing, dead, slow, or says `ok:false`.
    func request(_ body: [String: Any]) throws -> [String: Any] {
        lock.lock()
        guard let stdin = ensureRunning() else {
            lock.unlock()
            throw Failure.unavailable
        }
        let id = nextID
        nextID += 1
        let waiter = expect(id: id)
        lock.unlock()
        var line = body
        line["id"] = id
        writeLock.withLock { write(line, to: stdin) }

        waiter.wait()
        let response = lock.withLock {
            waiters[id] = nil
            if waiter.response?["ok"] as? Bool == true { exits = 0 }
            return waiter.response
        }
        guard let response else {
            throw Failure.error("file indexer did not answer \(body["op"] ?? "") (dead, or over \(Int(Self.timeout)) s)")
        }
        guard response["ok"] as? Bool == true else {
            throw Failure.error(response["error"] as? String ?? "file indexer refused \(body["op"] ?? "")")
        }
        return response
    }

    /// Register interest in the response carrying `id`. Caller holds the lock.
    func expect(id: Int) -> Waiter {
        let waiter = Waiter()
        waiters[id] = waiter
        return waiter
    }

    private func write(_ line: [String: Any], to handle: FileHandle) {
        guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
        data.append(0x0A)
        // A dead child closes the pipe; SIGPIPE is ignored process-wide by
        // Foundation, so this reports EPIPE as an error we can drop. The
        // reader thread sees the EOF and does the bookkeeping.
        try? handle.write(contentsOf: data)
    }

    // MARK: - Process

    /// Caller holds the lock. Spawns on first use, and once more after an
    /// unexpected exit; after that the launcher falls back to Spotlight rather
    /// than crash-looping a broken binary.
    private func ensureRunning() -> FileHandle? {
        if let stdin { return stdin }
        guard let binary, !shuttingDown, exits <= 1 else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            logger.error("file indexer failed to start: \(error.localizedDescription, privacy: .public)")
            exits = 2
            return nil
        }
        logger.notice("file indexer started (pid \(process.processIdentifier, privacy: .public))")
        self.process = process
        self.stdin = input.fileHandleForWriting
        buffer = Data()

        let reader = output.fileHandleForReading
        let thread = Thread { [weak self] in
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                self?.feed(data)
            }
            self?.childExited(process)
        }
        thread.name = "macotron-index reader"
        thread.start()

        if !observing {
            observing = true
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.shutdown() }
        }
        // A restart picks up where the dead process left off.
        if exits > 0, let lastConfigure {
            var line = lastConfigure
            line["id"] = nextID
            nextID += 1
            write(line, to: input.fileHandleForWriting)
        }
        return input.fileHandleForWriting
    }

    /// Feed raw stdout bytes; complete lines are dispatched to their waiters.
    /// A line without a known id is dropped: the spec says the child never
    /// speaks unprompted, so that is only ever a reply nobody waits for.
    func feed(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = json["id"] as? Int, let waiter = waiters.removeValue(forKey: id)
            else { continue }
            waiter.response = json
            waiter.semaphore.signal()
        }
    }

    private func childExited(_ exited: Process) {
        exited.waitUntilExit()
        lock.lock()
        defer { lock.unlock() }
        guard process === exited else { return }
        process = nil
        stdin = nil
        if !shuttingDown {
            exits += 1
            logger.error("file indexer exited with status \(exited.terminationStatus, privacy: .public)")
        }
        for waiter in waiters.values { waiter.semaphore.signal() }
        waiters.removeAll()
    }
}
