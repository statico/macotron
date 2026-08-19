// ShortcutsCLI.swift — /usr/bin/shortcuts list + run
import Foundation

enum ShortcutsCLI {
    static let binary = "/usr/bin/shortcuts"

    static func parseList(_ stdout: String) -> [String] {
        stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func list() -> [String] {
        parseList(run([binary, "list"]).stdout)
    }

    static func runShortcut(_ name: String) -> (ok: Bool, stdout: String, stderr: String) {
        let result = run([binary, "run", name])
        return (result.exitCode == 0, result.stdout, result.stderr)
    }

    private static func run(_ args: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, 1)
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}
