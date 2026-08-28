// Subprocess.swift — one way to run a tool and collect what it said.
//
// Thirteen copies of Process + Pipe + run/wait had grown across the modules,
// and they did not agree. Several waited on the process before draining its
// pipes, which deadlocks the moment a tool writes more than the 64K pipe
// buffer holds: the child blocks writing, the parent blocks waiting, and
// neither moves again. `shell.run` carried a comment warning about exactly
// that while its neighbours had the bug.
//
// So: read first, then wait. Always.
import Foundation

enum Subprocess {
    struct Result {
        var stdout: String
        var stderr: String
        var exitCode: Int32

        var ok: Bool { exitCode == 0 }
    }

    /// Run `path` with `args` and collect its output. A tool that cannot be
    /// launched at all reports its reason on stderr with a non-zero status,
    /// so callers handle "did not run" and "ran and failed" the same way.
    ///
    /// `stdin` is written and the pipe closed before output is read; without
    /// the close a tool reading to EOF never finishes.
    @discardableResult
    static func run(_ path: String, _ args: [String] = [], stdin: String? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = stdin.map { _ in Pipe() }
        if let input { process.standardInput = input }

        do {
            try process.run()
        } catch {
            return Result(stdout: "", stderr: error.localizedDescription, exitCode: 1)
        }

        if let input, let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            input.fileHandleForWriting.closeFile()
        }

        // Before waitUntilExit, never after: see the note at the top.
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}
