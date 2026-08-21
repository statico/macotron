// PluginAuthoring.swift — agents and editors offered for writing plugins
import AppKit
import Foundation

/// One entry in the Build Plugin menu. Agents run in Terminal; editors open the
/// workdir as an app. Everything is listed whether or not it is installed —
/// checking first would hide tools that LaunchServices simply has not indexed,
/// so the launch attempt is what reports a missing tool.
public struct PluginAuthoringTool: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Command run in Terminal, for agents that have no app of their own.
    public let command: String?
    /// Application name passed to `open -a`, for editors.
    public let app: String?

    public var isAgent: Bool { command != nil }
}

public enum PluginAuthoring {
    public static let agents: [PluginAuthoringTool] = [
        PluginAuthoringTool(id: "claude", name: "Claude Code", command: "claude", app: nil),
        PluginAuthoringTool(id: "codex", name: "Codex", command: "codex", app: nil),
        PluginAuthoringTool(id: "gemini", name: "Gemini CLI", command: "gemini", app: nil),
        PluginAuthoringTool(id: "cursor-agent", name: "Cursor CLI", command: "cursor-agent", app: nil),
    ]

    public static let editors: [PluginAuthoringTool] = [
        PluginAuthoringTool(id: "cursor", name: "Cursor", command: nil, app: "Cursor"),
        PluginAuthoringTool(id: "vscode", name: "Visual Studio Code", command: nil, app: "Visual Studio Code"),
        PluginAuthoringTool(id: "zed", name: "Zed", command: nil, app: "Zed"),
        PluginAuthoringTool(id: "xcode", name: "Xcode", command: nil, app: "Xcode"),
        PluginAuthoringTool(id: "terminal", name: "Terminal", command: nil, app: "Terminal"),
    ]

    /// Opens `directory` with the tool. Returns false when the tool could not be
    /// started, which for editors means the app is not installed. An agent whose
    /// command is missing still opens Terminal and reports there.
    @discardableResult
    public static func launch(_ tool: PluginAuthoringTool, in directory: URL) -> Bool {
        let path = directory.path(percentEncoded: false)
        if let command = tool.command {
            return run(["/usr/bin/osascript", "-e", terminalScript(command: command, in: path)])
        }
        guard let app = tool.app else { return false }
        return run(["/usr/bin/open", "-a", app, path])
    }

    /// AppleScript that opens a Terminal window in the workdir and starts the agent.
    static func terminalScript(command: String, in path: String) -> String {
        let script = "cd \(shellQuoted(path)) && clear && \(command)"
        return """
        tell application "Terminal"
            activate
            do script "\(appleScriptQuoted(script))"
        end tell
        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        return process.terminationStatus == 0
    }
}
