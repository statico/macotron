import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("fs.watch pointer safety")
struct FileSystemWatchSecurityTests {
    @Test("fs.watch survives JS tampering with $$__fsModule")
    func watchSurvivesTamperedGlobal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macotron-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = Engine()
        engine.addModule(FileSystemModule())
        engine.registerAllModules()

        let escaped = dir.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let (result, error) = engine.evaluate("""
            globalThis.$$__fsModule = 12345;
            var stop = macotron.fs.watch("\(escaped)", function() {});
            stop();
            "ok"
            """)
        #expect(error == nil)
        #expect(result == "ok")
    }

    @Test("no native pointer is exposed as a JS global")
    func noPointerGlobal() {
        let engine = Engine()
        engine.addModule(FileSystemModule())
        engine.registerAllModules()

        let (result, error) = engine.evaluate("typeof globalThis.$$__fsModule")
        #expect(error == nil)
        #expect(result == "undefined")
    }
}
