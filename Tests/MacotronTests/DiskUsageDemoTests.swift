import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("DiskUsageDemoTests")
struct DiskUsageDemoTests {
    private func eval(_ js: String) throws -> String {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/demo-disk-usage.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
            var macotron = { plugin: () => ({}), command: () => {}, panel: {}, shell: {}, notify: {} };
            \(demo)
            \(js)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("df keeps Macintosh HD and /Volumes, drops system slices")
    func parseVolumes() throws {
        let df = """
            Filesystem 1024-blocks Used Available Capacity Mounted on
            /dev/disk3s1s1 1948455240 16716080 822730596 2% /
            devfs 370 370 0 100% /dev
            /dev/disk3s6 1948455240 17825852 822730596 3% /System/Volumes/VM
            /dev/disk3s5 1948455240 1070017848 822730596 57% /System/Volumes/Data
            /dev/disk9s1 2107888 1621304 477280 78% /Volumes/Backup
            """
        let result = try eval("JSON.stringify(parseDf(" + String(reflecting: df) + "))")
        #expect(result.contains("Macintosh HD"))
        #expect(result.contains("Backup"))
        #expect(result.contains("/System/Volumes/Data"))
        #expect(!result.contains("\"path\":\"/\""))
        #expect(!result.contains("/dev"))
        #expect(!result.contains("/System/Volumes/VM"))
    }

    @Test("du lists children largest first and keeps a total")
    func parseListing() throws {
        let du = """
            1024\t/Users/alex/Photos
            2048\t/Users/alex/Library
            512\t/Users/alex/.zshrc
            4096\t/Users/alex
            """
        let result = try eval("JSON.stringify(parseDu(" + String(reflecting: du) + ", \"/Users/alex\"))")
        #expect(result.contains("Library"))
        #expect(result.contains("\"total\":4096"))
        #expect(result.contains("\"kb\":2048"))
    }

    @Test("back from home does not climb into /Users")
    func homeIsRoot() throws {
        let result = try eval(#"""
            JSON.stringify([
                parentPath("/Users/alex", "/Users/alex"),
                parentPath("/Users/alex/Documents", "/Users/alex"),
                parentPath("/Users/alex/Documents/Work", "/Users/alex")
            ])
            """#)
        #expect(result == #"["","/Users/alex","/Users/alex/Documents"]"#)
    }
}
