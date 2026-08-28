import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("fs.rename")
struct FileSystemRenameTests {
    @Test("moves a file and expands nothing extra on absolute paths")
    func movesFile() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("a.txt").path
            let dest = dir.appendingPathComponent("b.txt").path
            try "hi".write(toFile: src, atomically: true, encoding: .utf8)

            let (_, error) = fsEngine().evaluate("macotron.fs.rename(\(jsString(src)), \(jsString(dest)))")
            #expect(error == nil)
            #expect(FileManager.default.fileExists(atPath: dest))
            #expect(!FileManager.default.fileExists(atPath: src))
            #expect(try String(contentsOfFile: dest, encoding: .utf8) == "hi")
        }
    }

    @Test("throws when the destination already exists")
    func refusesOverwrite() throws {
        try withTempDir { dir in
            let src = dir.appendingPathComponent("a.txt").path
            let dest = dir.appendingPathComponent("b.txt").path
            try "a".write(toFile: src, atomically: true, encoding: .utf8)
            try "b".write(toFile: dest, atomically: true, encoding: .utf8)

            let (_, error) = fsEngine().evaluate("macotron.fs.rename(\(jsString(src)), \(jsString(dest)))")
            #expect(error != nil)
            #expect(try String(contentsOfFile: dest, encoding: .utf8) == "b")
        }
    }
}

@MainActor
@Suite("fs.readBytes")
struct FileSystemReadBytesTests {
    @Test("returns base64 of the file")
    func readsBytes() throws {
        try withTempDir { dir in
            let path = dir.appendingPathComponent("a.bin").path
            let data = Data([0, 1, 2, 255])
            try data.write(to: URL(fileURLWithPath: path))

            let (result, error) = fsEngine().evaluate("macotron.fs.readBytes(\(jsString(path)))")
            #expect(error == nil)
            #expect(result == data.base64EncodedString())
        }
    }
}

/// Runs `body` in a fresh temporary directory and removes it afterwards.
private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "macotron-fs-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

@MainActor
private func fsEngine() -> Engine {
    let engine = Engine()
    engine.addModule(FileSystemModule())
    engine.registerAllModules()
    return engine
}

private func jsString(_ path: String) -> String {
    "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
