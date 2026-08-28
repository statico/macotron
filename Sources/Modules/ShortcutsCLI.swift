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
        parseList(Subprocess.run(binary, ["list"]).stdout)
    }

    static func runShortcut(_ name: String) -> (ok: Bool, stdout: String, stderr: String) {
        let result = Subprocess.run(binary, ["run", name])
        return (result.ok, result.stdout, result.stderr)
    }
}
