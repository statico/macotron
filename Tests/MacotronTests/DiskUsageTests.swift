import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("DiskUsage")
struct DiskUsageTests {
    private func eval(_ js: String) throws -> String {
        try PluginHarness.eval(
            plugin: "disk-usage.js",
            mock: "var macotron = { plugin: () => ({}), command: () => {}, panel: {}, shell: {}, notify: {} };",
            extra: js)
    }

    @Test("volumes skip server shares and count purgeable space as free")
    func volumes() throws {
        let result = try eval(#"""
            JSON.stringify(volumeRows([
                { name: "Macintosh HD", path: "/", device: "disk3s1s1", total: 1048576000, available: 262144000, network: false },
                { name: "Backup", path: "/Volumes/Backup", device: "disk9s1", total: 2097152, available: 1048576, network: false },
                { name: "Share", path: "/Volumes/Share", device: "//nas/Share", total: 1024, available: 0, network: true }
            ]))
            """#)
        #expect(result == #"[{"name":"Macintosh HD","path":"/","device":"disk3s1s1","kb":768000,"total":1024000,"kind":"volume"},"#
            + #"{"name":"Backup","path":"/Volumes/Backup","device":"disk9s1","kb":1024,"total":2048,"kind":"volume"}]"#)
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
