import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("StorageStats")
struct StorageStatsTests {
    /// The plugin reaches for shell, checks and app at load time, so the mock
    /// has to answer all three before any parsing function can be called.
    private func eval(_ js: String) throws -> String {
        try PluginHarness.eval(
            plugin: "disk-usage.js",
            mock: """
                var macotron = {
                    plugin: () => ({}),
                    command: () => {},
                    panel: { open: () => 1, postMessage: () => {}, onMessage: () => {} },
                    shell: { run: () => Promise.resolve({ stdout: "", stderr: "", exitCode: 0 }) },
                    notify: { toast: () => {} },
                    fs: { exists: () => false, list: () => [] },
                    app: { list: () => [] },
                    checks: () => {},
                    confirm: () => false
                };
                """,
            extra: js)
    }

    @Test("diskutil info reads as key/value pairs")
    func parseInfo() throws {
        let info = """
               Device Identifier:         disk3s1s1
               Volume Name:               Macintosh HD
               SMART Status:              Verified
               Disk Size:                 994.7 GB (994662584320 Bytes) (exactly 1942700360 512-Byte-Units)
               Solid State:               Yes
            """
        let result = try eval("JSON.stringify(parseDiskutil(" + String(reflecting: info) + "))")
        #expect(result.contains(#""Device Identifier":"disk3s1s1""#))
        #expect(result.contains(#""Volume Name":"Macintosh HD""#))
        #expect(result.contains(#""SMART Status":"Verified""#))
        // The value keeps everything after the first colon, parentheses included.
        #expect(result.contains(#"994662584320 Bytes"#))
    }

    @Test("Verified is healthy")
    func smartVerified() throws {
        let info = """
               Device Identifier:         disk3s1s1
               SMART Status:              Verified
            """
        let result = try eval("JSON.stringify(smartOf(parseDiskutil(" + String(reflecting: info) + ")))")
        #expect(result.contains(#""status":"Verified""#))
        #expect(result.contains(#""known":true"#))
        #expect(result.contains(#""ok":true"#))
    }

    @Test("a volume with no SMART line is unknown, not failing")
    func smartMissing() throws {
        // Disk images and most external enclosures report no SMART at all.
        let info = """
               Device Identifier:         disk5s1
               Volume Name:               Backup
               Disk Size:                 2.0 TB (2000000000000 Bytes)
            """
        let result = try eval("JSON.stringify(smartOf(parseDiskutil(" + String(reflecting: info) + ")))")
        #expect(result.contains(#""known":false"#))
        #expect(result.contains(#""ok":true"#))
    }

    @Test("a SMART status other than Verified fails the check")
    func smartFailing() throws {
        let info = "   SMART Status:              Failing"
        let result = try eval("JSON.stringify(smartOf(parseDiskutil(" + String(reflecting: info) + ")))")
        #expect(result.contains(#""ok":false"#))
    }

    @Test("iostat reports the last sample, not the average since boot")
    func parseSample() throws {
        let out = """
                          disk0               disk4               disk6
                KB/t  tps  MB/s     KB/t  tps  MB/s     KB/t  tps  MB/s
               19.70  205  3.94     4.05    0  0.00     4.00    1  0.00
                6.04   53  0.31     0.00    0  0.00     0.00    0  0.00
            """
        let result = try eval("JSON.stringify(parseIostat(" + String(reflecting: out) + "))")
        #expect(result.contains(#""name":"disk0""#))
        #expect(result.contains(#""name":"disk4""#))
        #expect(result.contains(#""name":"disk6""#))
        // Second row: 6.04 KB/t, 53 tps, 0.31 MB/s -- the one-second sample.
        #expect(result.contains(#""kbPerTransfer":6.04,"tps":53,"mbPerSec":0.31"#))
        // The since-boot averages from the first row must not survive.
        #expect(!result.contains("3.94"))
        #expect(!result.contains("205"))
    }

    @Test("a single disk still parses")
    func parseOneDisk() throws {
        let out = """
                          disk0
                KB/t  tps  MB/s
               19.70  205  3.94
                6.04   53  0.31
            """
        let result = try eval("JSON.stringify(parseIostat(" + String(reflecting: out) + "))")
        #expect(result.contains(#""name":"disk0""#))
        #expect(result.contains(#""mbPerSec":0.31"#))
        #expect(!result.contains("disk1"))
    }

    @Test("iostat's physical disk joins to a df slice")
    func sliceToDisk() throws {
        let result = try eval(#"""
            JSON.stringify([physicalDisk("disk3s1s1"), physicalDisk("disk12s2"), physicalDisk("")])
            """#)
        #expect(result == #"["disk3","disk12",""]"#)
    }

    @Test("only reverse-DNS names are attributed to an app")
    func bundleIds() throws {
        let result = try eval(#"""
            JSON.stringify([
                bundleIdOf("com.example.Thing"),
                bundleIdOf("com.example.Thing.plist"),
                bundleIdOf("com.example.Thing.savedState"),
                bundleIdOf("Sublime Text"),
                bundleIdOf("com.example")
            ])
            """#)
        #expect(result == #"["com.example.Thing","com.example.Thing","com.example.Thing","",""]"#)
    }

    @Test("trashing goes through Finder with the paths as arguments")
    func trashesViaFinder() throws {
        let result = try eval(#"JSON.stringify(trashScript(["/a/b", "/c/d"]))"#)
        // Finder's delete trashes rather than erases, so it stays recoverable.
        #expect(result.contains("tell application \\\"Finder\\\" to delete doomed"))
        // The paths must land after the script, never spliced into it.
        #expect(result.hasSuffix(#""/a/b","/c/d"]"#))
    }
}
