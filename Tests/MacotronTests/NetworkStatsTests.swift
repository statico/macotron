import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("NetworkStats")
struct NetworkStatsTests {
    /// Every test drives the same plugin, so the mock lives once.
    static let mock = #"""
        var counters = [{ name: "en0", bytesIn: 1000, bytesOut: 2000 }];
        var statusConfig = null;
        var stored = {};
        var localStorage = {
            getItem: (key) => (key in stored ? stored[key] : null),
            setItem: (key, value) => { stored[key] = String(value); }
        };
        var macotron = {
            plugin: () => ({}),
            network: {
                counters: () => counters,
                ping: () => Promise.resolve({ ms: 10 })
            },
            shell: { run: () => Promise.resolve({ stdout: "", stderr: "", exitCode: 0 }) },
            menubar: { status: (id, cfg) => { statusConfig = cfg; } },
            checks: () => {},
            every: () => {},
            at: () => {}
        };
        """#

    @Test("nettop parser skips the header and reads dotted process names")
    func parse() throws {
        let result = try PluginHarness.eval(plugin: "network-path.js", mock: Self.mock, extra: #"""
            JSON.stringify(parseNettop(
                ",bytes_in,bytes_out,\n" +
                "kernel_task.0,10285443228,1781780052,\n" +
                "com.apple.WebKit.Networking.421,10,20,\n"
            ));
            """#)
        // The header row has no pid, so it must not read as a process.
        #expect(!result.contains("bytes_in"))
        #expect(result.contains("{\"name\":\"kernel_task\",\"pid\":0,\"bytesIn\":10285443228,\"bytesOut\":1781780052}"))
        // The pid is the last dotted segment, not the second one.
        #expect(result.contains("{\"name\":\"com.apple.WebKit.Networking\",\"pid\":421,\"bytesIn\":10,\"bytesOut\":20}"))
    }

    @Test("only positive counter deltas reach the session total")
    func sessionTotal() throws {
        let result = try PluginHarness.eval(plugin: "network-path.js", mock: Self.mock, extra: #"""
            counters = [{ name: "en0", bytesIn: 1100, bytesOut: 2000 }];
            rates();
            // An interface that dropped restarts its counters: not 1040 bytes back.
            counters = [{ name: "en0", bytesIn: 10, bytesOut: 2000 }];
            rates();
            counters = [{ name: "en0", bytesIn: 60, bytesOut: 2000 }];
            rates();
            JSON.stringify(session);
            """#)
        #expect(result.contains("\"in\":150"))
        #expect(result.contains("\"out\":0"))
    }
}
