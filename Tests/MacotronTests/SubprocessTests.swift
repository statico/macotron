import Testing
@testable import Modules

@Suite("Subprocess")
struct SubprocessTests {
    @Test("captures stdout, stderr and status separately")
    func streams() {
        let result = Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
        #expect(result.exitCode == 3)
        #expect(!result.ok)
    }

    @Test("output larger than the pipe buffer does not deadlock")
    func largeOutput() {
        // The reason this helper exists. A tool writing past the 64K pipe
        // buffer blocks until someone drains it, so a runner that waits for
        // the process before reading hangs here forever rather than failing.
        let result = Subprocess.run("/bin/sh", ["-c", "yes abcdefgh | head -c 300000"])
        #expect(result.stdout.count == 300_000)
        #expect(result.ok)
    }

    @Test("stdin is written and closed so the tool sees EOF")
    func stdinIsClosed() {
        // `cat` with no argument reads until EOF: if the pipe is left open it
        // never returns and this test hangs.
        let result = Subprocess.run("/bin/cat", stdin: "hello")
        #expect(result.stdout == "hello")
        #expect(result.ok)
    }

    @Test("a binary that does not exist reports rather than crashes")
    func missingBinary() {
        let result = Subprocess.run("/nonexistent/tool", ["--version"])
        #expect(!result.ok)
        #expect(!result.stderr.isEmpty)
    }
}
