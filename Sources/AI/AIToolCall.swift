// AIToolCall.swift — Tool-call-based file management for AI
// The AI uses tools to read/write/delete modules rather than direct fs access.
// This provides an audit trail and triggers backups automatically.
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai-tools")

/// Tool definitions provided to AI models for module management
@MainActor
public enum AIToolDefinition {
    public static let tools: [[String: Any]] = [
        [
            "name": "read_module",
            "description": "Read the contents of a module or command file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename (e.g., 001-window-tiling.js)"],
                    "directory": ["type": "string", "enum": ["modules", "commands"], "description": "Which directory to read from"]
                ],
                "required": ["filename"]
            ]
        ],
        [
            "name": "write_module",
            "description": "Create or overwrite a module or command file. Automatically backs up config first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename (e.g., 006-my-feature.js)"],
                    "content": ["type": "string", "description": "The JavaScript source code"],
                    "directory": ["type": "string", "enum": ["modules", "commands"], "description": "Which directory to write to"]
                ],
                "required": ["filename", "content"]
            ]
        ],
        [
            "name": "delete_module",
            "description": "Delete a module or command file. Automatically backs up config first.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "filename": ["type": "string", "description": "The filename to delete"],
                    "directory": ["type": "string", "enum": ["modules", "commands"], "description": "Which directory to delete from"]
                ],
                "required": ["filename"]
            ]
        ],
        [
            "name": "list_modules",
            "description": "List all module and command files with descriptions",
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
        moduleManager: ModuleManager
    ) -> String {
        switch toolName {
        case "read_module":
            return executeReadModule(input: input, moduleManager: moduleManager)
        case "write_module":
            return executeWriteModule(input: input, moduleManager: moduleManager)
        case "delete_module":
            return executeDeleteModule(input: input, moduleManager: moduleManager)
        case "list_modules":
            return executeListModules(moduleManager: moduleManager)
        case "read_config":
            return executeReadConfig(moduleManager: moduleManager)
        case "write_config":
            return executeWriteConfig(input: input, moduleManager: moduleManager)
        default:
            return "Unknown tool: \(toolName)"
        }
    }

    private static func executeReadModule(input: [String: Any], moduleManager: ModuleManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let directory = input["directory"] as? String ?? "modules"
        let file = moduleManager.configDir.appending(path: directory).appending(path: filename)
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return "Error: File not found: \(directory)/\(filename)"
        }
        return content
    }

    private static func executeWriteModule(input: [String: Any], moduleManager: ModuleManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let content = input["content"] as? String ?? ""
        let directory = input["directory"] as? String ?? "modules"

        guard !filename.isEmpty, !content.isEmpty else {
            return "Error: filename and content are required"
        }

        // Capability review before writing
        let manifest = CapabilityReview.review(content)
        logger.info("Writing \(directory)/\(filename) — tier: \(String(describing: manifest.tier)), APIs: \(manifest.apisUsed)")

        if moduleManager.writeModule(filename: filename, content: content, directory: directory) {
            // Auto-reload
            moduleManager.reloadAll()
            return "Successfully wrote \(directory)/\(filename)"
        } else {
            return "Error: Failed to write \(directory)/\(filename)"
        }
    }

    private static func executeDeleteModule(input: [String: Any], moduleManager: ModuleManager) -> String {
        let filename = input["filename"] as? String ?? ""
        let directory = input["directory"] as? String ?? "modules"

        guard !filename.isEmpty else {
            return "Error: filename is required"
        }

        if moduleManager.deleteModule(filename: filename, directory: directory) {
            moduleManager.reloadAll()
            return "Successfully deleted \(directory)/\(filename)"
        } else {
            return "Error: Failed to delete \(directory)/\(filename)"
        }
    }

    private static func executeListModules(moduleManager: ModuleManager) -> String {
        let modules = moduleManager.listModules(directory: "modules")
        let commands = moduleManager.listModules(directory: "commands")

        var output = "Modules:\n"
        for s in modules {
            output += "  \(s.filename) — \(s.description)\n"
        }
        output += "\nCommands:\n"
        for c in commands {
            output += "  \(c.filename) — \(c.description)\n"
        }
        return output
    }

    private static func executeReadConfig(moduleManager: ModuleManager) -> String {
        let configFile = moduleManager.configDir.appending(path: "config.js")
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else {
            return "Error: config.js not found"
        }
        return content
    }

    private static func executeWriteConfig(input: [String: Any], moduleManager: ModuleManager) -> String {
        let content = input["content"] as? String ?? ""
        guard !content.isEmpty else {
            return "Error: content is required"
        }

        moduleManager.backup.createBackup()
        let configFile = moduleManager.configDir.appending(path: "config.js")
        do {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
            moduleManager.reloadAll()
            return "Successfully wrote config.js"
        } catch {
            return "Error: Failed to write config.js: \(error.localizedDescription)"
        }
    }
}
