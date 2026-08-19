import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("fs.rename")
struct FileSystemRenameTests {
    @Test("moves a file and expands nothing extra on absolute paths")
    func movesFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macotron-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("a.txt").path
        let dest = dir.appendingPathComponent("b.txt").path
        try "hi".write(toFile: src, atomically: true, encoding: .utf8)

        let engine = Engine()
        engine.addModule(FileSystemModule())
        engine.registerAllModules()
        let (_, error) = engine.evaluate("macotron.fs.rename(\(jsString(src)), \(jsString(dest)))")
        #expect(error == nil)
        #expect(FileManager.default.fileExists(atPath: dest))
        #expect(!FileManager.default.fileExists(atPath: src))
        #expect(try String(contentsOfFile: dest, encoding: .utf8) == "hi")
    }

    @Test("throws when the destination already exists")
    func refusesOverwrite() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macotron-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("a.txt").path
        let dest = dir.appendingPathComponent("b.txt").path
        try "a".write(toFile: src, atomically: true, encoding: .utf8)
        try "b".write(toFile: dest, atomically: true, encoding: .utf8)

        let engine = Engine()
        engine.addModule(FileSystemModule())
        engine.registerAllModules()
        let (_, error) = engine.evaluate("macotron.fs.rename(\(jsString(src)), \(jsString(dest)))")
        #expect(error != nil)
        #expect(try String(contentsOfFile: dest, encoding: .utf8) == "b")
    }
}

private func jsString(_ path: String) -> String {
    "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
