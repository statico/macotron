import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("dryRun stubs")
@MainActor
struct DryRunStubTests {
    @Test("fs.write does not touch disk")
    func fsWrite() throws {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "macotron-dryrun-\(UUID().uuidString).txt").path
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(FileSystemModule())
        engine.registerAllModules()
        let (_, error) = engine.evaluate("macotron.fs.write(\(jsString(path)), 'nope')")
        #expect(error == nil)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("http.get does not use the network")
    func httpGet() {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(HTTPModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate(
            "JSON.stringify(macotron.http.get('https://example.invalid/'))"
        )
        #expect(error == nil)
        #expect(result?.contains("\"status\":0") == true)
    }

    private func jsString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
