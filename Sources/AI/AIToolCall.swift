// AIToolCall.swift — Tool-call-based file management for AI
// The AI uses tools to read/write/delete snippets rather than direct fs access.
// This provides an audit trail and triggers backups automatically.
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai-tools")

/// Tool definitions provided to AI models for snippet management
@MainActor
public enum AIToolDefinition {
    public static let tools: [[String: Any]] = [
        [
            "name": "read_snippet",
            "description": "Read the contents of a snippet or command file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename (e.g., 001-window-tiling.js)"],
                    "directory": ["type": "string", "enum": ["snippets", "commands"], "description": "Which directory to read from"]
                ],
                "required": ["filename"]
            ]
        ],
        [
            "name": "write_snippet",
            "description": "Create or overwrite a snippet or command file. Automatically backs up config first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename (e.g., 006-my-feature.js)"],
                    "content": ["type": "string", "description": "The JavaScript source code"],
                    "directory": ["type": "string", "enum": ["snippets", "commands"], "description": "Which directory to write to"]
                ],
                "required": ["filename", "content"]
            ]
        ],
        [
            "name": "delete_snippet",
            "description": "Delete a snippet or command file. Automatically backs up config first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename to delete"],
                    "directory": ["type": "string", "enum": ["snippets", "commands"], "description": "Which directory to delete from"]
                ],
                "required": ["filename"]
            ]
        ],
        [
            "name": "list_snippets",
            "description": "List all snippet and command files with descriptions",
            "input_schema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "read_config",
            "description": "Read the current config.js contents",
            "input_schema": [
                "type": "object",
                "properties": [:]
            ]
        ],
        [
            "name": "write_config",
            "description": "Update config.js contents. Automatically backs up config first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "content": ["type": "string", "description": "The new config.js source code"]
                ],
                "required": ["content"]
            ]
        ],
    ]

    /// Execute a tool call and return the result
    public static func execute(
        toolName: String,
        input: [String: Any],
        snippetManager: SnippetManager
    ) -> String {
        switch toolName {
        case "read_snippet":
            return executeReadSnippet(input: input, snippetManager: snippetManager)
        case "write_snippet":
            return executeWriteSnippet(input: input, snippetManager: snippetManager)
        case "delete_snippet":
            return executeDeleteSnippet(input: input, snippetManager: snippetManager)
        case "list_snippets":
            return executeListSnippets(snippetManager: snippetManager)
        case "read_config":
            return executeReadConfig(snippetManager: snippetManager)
        case "write_config":
            return executeWriteConfig(input: input, snippetManager: snippetManager)
        default:
            return "Unknown tool: \(toolName)"
        }
    }

    private static func executeReadSnippet(input: [String: Any], snippetManager: SnippetManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let directory = input["directory"] as? String ?? "snippets"
        let file = snippetManager.configDir.appending(path: directory).appending(path: filename)
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return "Error: File not found: \(directory)/\(filename)"
        }
        return content
    }

    private static func executeWriteSnippet(input: [String: Any], snippetManager: SnippetManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let content = input["content"] as? String ?? ""
        let directory = input["directory"] as? String ?? "snippets"

        guard !filename.isEmpty, !content.isEmpty else {
            return "Error: filename and content are required"
        }

        // Capability review before writing
        let manifest = CapabilityReview.review(content)
        logger.info("Writing \(directory)/\(filename) — tier: \(String(describing: manifest.tier)), APIs: \(manifest.apisUsed)")

        if snippetManager.writeSnippet(filename: filename, content: content, directory: directory) {
            // Auto-reload
            snippetManager.reloadAll()
            return "Successfully wrote \(directory)/\(filename)"
        } else {
            return "Error: Failed to write \(directory)/\(filename)"
        }
    }

    private static func executeDeleteSnippet(input: [String: Any], snippetManager: SnippetManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let directory = input["directory"] as? String ?? "snippets"

        guard !filename.isEmpty else {
            return "Error: filename is required"
        }

        if snippetManager.deleteSnippet(filename: filename, directory: directory) {
            snippetManager.reloadAll()
            return "Successfully deleted \(directory)/\(filename)"
        } else {
            return "Error: Failed to delete \(directory)/\(filename)"
        }
    }

    private static func executeListSnippets(snippetManager: SnippetManager) -> String {
        let snippets = snippetManager.listSnippets(directory: "snippets")
        let commands = snippetManager.listSnippets(directory: "commands")

        var output = "Snippets:\n"
        for s in snippets {
            output += "  \(s.filename) — \(s.description)\n"
        }
        output += "\nCommands:\n"
        for c in commands {
            output += "  \(c.filename) — \(c.description)\n"
        }
        return output
    }

    private static func executeReadConfig(snippetManager: SnippetManager) -> String {
        let configFile = snippetManager.configDir.appending(path: "config.js")
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else {
            return "Error: config.js not found"
        }
        return content
    }

    private static func executeWriteConfig(input: [String: Any], snippetManager: SnippetManager) -> String {
        let content = input["content"] as? String ?? ""
        guard !content.isEmpty else {
            return "Error: content is required"
        }

        snippetManager.backup.createBackup()
        let configFile = snippetManager.configDir.appending(path: "config.js")
        do {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
            snippetManager.reloadAll()
            return "Successfully wrote config.js"
        } catch {
            return "Error: Failed to write config.js: \(error.localizedDescription)"
        }
    }
}
