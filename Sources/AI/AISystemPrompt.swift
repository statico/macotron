// AISystemPrompt.swift — Builds system prompts for AI sessions
import Foundation
import MacotronEngine

/// Assembles system prompts for the AI agent and auto-fix sessions.
/// Uses a stable prefix (type defs, tools, rules) for KV-cache efficiency,
/// with dynamic context (snippet inventory, errors) appended at the end.
@MainActor
public enum AISystemPrompt {

    // MARK: - Agent Prompt (primary)

    /// Build the agent-oriented system prompt with stable prefix and dynamic suffix.
    /// - Parameter snippetManager: The snippet manager to query for current state.
    /// - Returns: The assembled system prompt string.
    public static func buildAgentPrompt(snippetManager: SnippetManager) -> String {
        var parts: [String] = []

        // Stable prefix — rarely changes, maximizes KV-cache hits

        parts.append("""
        You are Macotron's coding agent. Macotron is a macOS automation tool that runs JavaScript \
        snippets to control windows, keyboard shortcuts, system events, and more.

        You are an AUTONOMOUS AGENT, not a chatbot. When given a command:
        1. Plan what scripts to create or modify.
        2. Execute tool calls to write the scripts.
        3. The engine will reload automatically after each write.
        4. Check for errors. If any, fix them (up to 2 repair attempts).
        5. Report success or failure.

        RULES:
        - Act immediately. Do not ask clarifying questions — make reasonable assumptions.
        - Use the macotron.d.ts API below. Do not invent APIs that do not exist.
        - Snippet filenames follow the pattern: NNN-description.js (e.g., 005-window-tiling.js).
        - Pick the next available number prefix when creating new snippets.
        - Every snippet file MUST start with a // comment describing what it does.
        - Write COMPLETE files, not patches. The write_snippet tool overwrites the entire file.
        - Keep scripts focused — one concern per file.
        - Never output raw code to the user. Use write_snippet to save code directly.
        - If a write fails validation, read the error, fix the script, and retry.
        """)

        // Type definitions
        if let typeDefs = loadTypeDefinitions() {
            parts.append("""
            ## Macotron JavaScript API (macotron.d.ts)

            ```typescript
            \(typeDefs)
            ```
            """)
        }

        // Example patterns (brief)
        parts.append("""
        ## Patterns

        Keyboard shortcut: `macotron.keyboard.on("ctrl+opt+left", () => { ... })`
        Periodic task: `macotron.every(30000, async () => { ... })`
        Command: `macotron.command("name", "description", async () => { ... })`
        Menubar item: `macotron.menubar.add("id", { title, icon, onClick })`
        """)

        // Tool usage
        parts.append("""
        ## Tools

        - `list_snippets` — See what's currently installed
        - `read_snippet` — Read existing code before modifying
        - `write_snippet` — Create or overwrite a snippet (backs up first, triggers reload)
        - `delete_snippet` — Remove a snippet (backs up first, triggers reload)
        - `read_config` — Read config.js
        - `write_config` — Update config.js (backs up first, triggers reload)
        """)

        // Dynamic suffix — changes per request

        // Current snippet inventory
        parts.append(buildSnippetInventory(snippetManager: snippetManager))

        return parts.joined(separator: "\n\n")
    }

    /// Format reload errors for injection into the agent's context as a user message.
    /// - Parameter errors: The error tuples from SnippetManager.lastReloadErrors
    /// - Returns: A formatted string describing the errors, or nil if no errors.
    public static func formatFailureTrace(errors: [(filename: String, error: String)]) -> String? {
        guard !errors.isEmpty else { return nil }

        var lines = ["RELOAD ERRORS — fix these:"]
        for err in errors {
            lines.append("  \(err.filename): \(err.error)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Chat Prompt (used by SnippetAutoFix)

    /// Build the chat-oriented system prompt. Used by SnippetAutoFix for backwards compatibility.
    public static func buildChatPrompt(snippetManager: SnippetManager) -> String {
        // Delegate to the original implementation
        return build(snippetManager: snippetManager)
    }

    /// Original chat system prompt — kept for SnippetAutoFix compatibility.
    public static func build(snippetManager: SnippetManager) -> String {
        var parts: [String] = []

        parts.append("""
        You are Macotron's built-in AI assistant. Macotron is a macOS automation tool that runs \
        JavaScript snippets to control windows, keyboard shortcuts, system events, and more.

        Your job is to help the user manage their Macotron configuration by reading, writing, and \
        deleting snippet files. You communicate in plain English and use tool calls to perform \
        file operations.

        IMPORTANT RULES:
        - Always explain what you will do BEFORE making tool calls.
        - When writing snippets, use the macotron.d.ts API below. Do not invent APIs that do not exist.
        - Snippet filenames follow the pattern: NNN-description.js (e.g., 005-window-tiling.js).
        - When creating a new snippet, pick the next available number prefix.
        - Every snippet file should start with a // comment describing what it does.
        - Keep responses concise. One to three sentences for explanations, then act.
        - If the user asks something unrelated to Macotron, answer briefly but note you are best at Macotron tasks.
        - Never output raw code blocks to the user unless they explicitly ask to see the code. \
          Instead, describe what the code does and use write_snippet to save it.
        """)

        if let typeDefs = loadTypeDefinitions() {
            parts.append("""
            ## Macotron JavaScript API (macotron.d.ts)

            ```typescript
            \(typeDefs)
            ```
            """)
        }

        parts.append("""
        ## Example Snippet Patterns

        Window tiling with keyboard shortcuts:
        ```javascript
        macotron.keyboard.on("ctrl+opt+left", () => {
            const win = macotron.window.focused();
            if (win) macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 0.5, h: 1 });
        });
        ```

        Periodic monitoring:
        ```javascript
        macotron.every(30000, async () => {
            const temp = await macotron.system.cpuTemp();
            if (temp > 90) macotron.notify.show("CPU Alert", `Temperature: ${temp}C`);
        });
        ```
        """)

        parts.append(buildSnippetInventory(snippetManager: snippetManager))

        parts.append("""
        ## Tool Usage

        You have tools to manage snippet files. Use them to fulfill user requests:
        - Use `list_snippets` to see what is currently installed.
        - Use `read_snippet` to inspect existing code before modifying it.
        - Use `write_snippet` to create or update snippets. Always include a descriptive // comment as the first line.
        - Use `delete_snippet` to remove snippets the user no longer wants.
        - Use `read_config` to inspect the user's config.js.
        - Use `write_config` to update the user's config.js.

        Every write and delete operation automatically creates a backup, so changes are safe and reversible.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Shared Helpers

    private static func buildSnippetInventory(snippetManager: SnippetManager) -> String {
        let snippets = snippetManager.listSnippets(directory: "snippets")
        let commands = snippetManager.listSnippets(directory: "commands")

        var inventoryText = "## Current Snippet Inventory\n\n"
        if snippets.isEmpty && commands.isEmpty {
            inventoryText += "No snippets or commands are currently installed.\n"
        } else {
            if !snippets.isEmpty {
                inventoryText += "Snippets:\n"
                for s in snippets {
                    inventoryText += "  - \(s.filename)"
                    if !s.description.isEmpty {
                        inventoryText += " \u{2014} \(s.description)"
                    }
                    inventoryText += "\n"
                }
            }
            if !commands.isEmpty {
                inventoryText += "\nCommands:\n"
                for c in commands {
                    inventoryText += "  - \(c.filename)"
                    if !c.description.isEmpty {
                        inventoryText += " \u{2014} \(c.description)"
                    }
                    inventoryText += "\n"
                }
            }
        }
        return inventoryText
    }

    /// Load macotron.d.ts from the app bundle.
    private static func loadTypeDefinitions() -> String? {
        if let url = Bundle.main.url(forResource: "macotron", withExtension: "d.ts") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "macotron", withExtension: "d.ts") {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }
}
