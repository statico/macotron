import Foundation
import Testing
@testable import Modules

@Suite("FileIndex")
struct FileIndexTests {
    private static let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("macotron-fileindex-\(UUID().uuidString)")

    /// An executable file where the binary is expected, so discovery can be
    /// checked without a Rust build.
    private static func stub(_ name: String) throws -> String {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let path = scratch.appendingPathComponent(name).path
        try "#!/bin/sh\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test("responses are matched to their waiter by id, whatever the order and chunking")
    func dispatch() {
        let index = FileIndex(binary: nil)
        let first = index.expect(id: 1)
        let second = index.expect(id: 2)
        // Two lines, the second answered first, and a line cut mid-object.
        index.feed(Data((#"{"id":2,"ok":true,"entries":3}"# + "\n{\"id\":1,\"ok\":tr").utf8))
        second.wait(1)
        #expect(second.response?["entries"] as? Int == 3)
        #expect(first.response == nil)
        index.feed(Data("ue,\"results\":[{\"path\":\"/a\"}]}\n".utf8))
        first.wait(1)
        let rows = first.response?["results"] as? [[String: Any]]
        #expect(rows?.first?["path"] as? String == "/a")
        // A reply nobody waits for, and garbage, are both dropped quietly.
        index.feed(Data("{\"id\":9,\"ok\":true}\nnot json\n".utf8))
        let third = index.expect(id: 3)
        third.wait(0.05)
        #expect(third.response == nil)
    }

    @Test("the env var wins over the bundle and the cargo build")
    func locate() throws {
        let env = try Self.stub("env-index")
        let bundled = try Self.stub("macotron-index")
        let cwd = Self.scratch.appendingPathComponent("cwd")
        try FileManager.default.createDirectory(
            at: cwd.appendingPathComponent("Indexer/target/release"), withIntermediateDirectories: true)
        let local = try Self.stub("cwd/Indexer/target/release/macotron-index")

        #expect(FileIndex.locate(environment: ["MACOTRON_INDEXER": env],
                                 executableDir: Self.scratch, cwd: cwd.path) == env)
        #expect(FileIndex.locate(environment: [:], executableDir: Self.scratch, cwd: cwd.path) == bundled)
        #expect(FileIndex.locate(environment: [:], executableDir: nil, cwd: cwd.path) == local)
        #expect(FileIndex.locate(environment: ["MACOTRON_INDEXER": "/nonexistent"],
                                 executableDir: nil, cwd: "/nonexistent") == nil)
    }

    @Test("without a binary every request reports unavailable instead of hanging")
    func unavailable() {
        let index = FileIndex(binary: nil)
        #expect(!index.available)
        #expect(throws: FileIndex.Failure.self) { try index.status() }
        #expect(throws: FileIndex.Failure.self) { try index.search(query: "x") }
        #expect(throws: Never.self) { try index.search(query: "  ") }
    }

    /// A shell script standing in for the indexer: echoes the request back as
    /// the response, so the test sees exactly what was sent.
    @Test("requests go out as one JSON line each, with ~ expanded")
    func roundTrip() throws {
        let fake = try Self.stub("echo-index")
        try #"""
            #!/bin/sh
            while IFS= read -r line; do
              printf '%s\n' "$line" | sed 's/"op"/"ok":true,"echo":true,"op"/'
            done
            """#.write(toFile: fake, atomically: true, encoding: .utf8)
        let index = FileIndex(binary: fake)
        let sent = try index.configure(roots: ["~/Documents", "/Applications"], ignore: ["*.tmp"],
                                       hidden: false, ignoreFiles: true)
        #expect(sent["roots"] as? [String] == [NSHomeDirectory() + "/Documents", "/Applications"])
        #expect(sent["ignoreFiles"] as? Bool == true)
        let status = try index.status()
        #expect(status["echo"] as? Bool == true)
        #expect(status["id"] as? Int == 2)
        // The echo carries no results; an empty query never leaves the host.
        #expect(try index.search(query: "abc", folder: "~", kind: ".pdf").isEmpty)
        index.shutdown()
    }

    @Test("an ok:false reply becomes an error with the indexer's message")
    func refused() throws {
        let fake = try Self.stub("refusing-index")
        try #"""
            #!/bin/sh
            while IFS= read -r line; do
              id=$(printf '%s' "$line" | sed 's/.*"id":\([0-9]*\).*/\1/')
              printf '{"id":%s,"ok":false,"error":"nope"}\n' "$id"
            done
            """#.write(toFile: fake, atomically: true, encoding: .utf8)
        let index = FileIndex(binary: fake)
        #expect(throws: FileIndex.Failure.self) { try index.reindex() }
        do {
            try index.reindex()
        } catch {
            #expect("\(error)" == "nope")
        }
        index.shutdown()
    }

    @Test("the real indexer finds a file in a temp root")
    func integration() throws {
        guard let binary = FileIndex.locate(environment: [:], executableDir: nil) else {
            print("FileIndex integration: Indexer/target/release/macotron-index not built; skipped")
            return
        }
        let root = Self.scratch.appendingPathComponent("root")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Docs"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("Docs/Q3 Budget.pdf"), atomically: true, encoding: .utf8)

        let index = FileIndex(binary: binary)
        try index.configure(roots: [root.path], ignore: [], hidden: false, ignoreFiles: true)
        var rows: [[String: Any]] = []
        for _ in 0..<50 where rows.isEmpty {
            rows = try index.search(query: "budget", kind: "pdf")
            if rows.isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        }
        #expect(rows.first?["name"] as? String == "Q3 Budget.pdf")
        #expect(rows.first?["isDir"] as? Bool == false)
        #expect(try index.status()["available"] == nil) // the host adds that field, not the child
        index.shutdown()
    }
}
