// AISystemPrompt.swift — Builds the system prompt for AI chat sessions
import Foundation
import MacotronEngine

/// Assembles the system prompt provided to the AI when processing launcher chat messages.
/// Includes type definitions, current snippet list, and behavioral instructions.
@MainActor
public enum AISystemPrompt {

    /// Build the full system prompt, including type definitions and current snippet inventory.
    /// - Parameter snippetManager: The snippet manager to query for current snippet list.
    /// - Returns: The assembled system prompt string.
    public static func build(snippetManager: SnippetManager) -> String {
        var parts: [String] = []

        // Section 1: Role and behavioral instructions
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

        // Section 2: Type definitions
        let typeDefinitions = loadTypeDefinitions()
        if let typeDefs = typeDefinitions {
            parts.append("""
            ## Macotron JavaScript API (macotron.d.ts)

            ```typescript
            \(typeDefs)
            ```
            """)
        }

        // Section 3: Example patterns
        parts.append("""
        ## Example Snippet Patterns

        Window tiling with keyboard shortcuts:
        ```javascript
        // Window tiling — Ctrl+Opt+Arrow to tile windows
        macotron.keyboard.on("ctrl+opt+left", () => {
            const win = macotron.window.focused();
            if (win) macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 0.5, h: 1 });
        });
        ```

        Periodic monitoring:
        ```javascript
        // CPU temperature monitor — shows notification when CPU is hot
        macotron.every(30000, async () => {
            const temp = await macotron.system.cpuTemp();
            if (temp > 90) macotron.notify.show("CPU Alert", `Temperature: ${temp}C`);
        });
        ```

        Custom command:
        ```javascript
        // Toggle dark mode command
        macotron.command("dark-mode", "Toggle macOS dark mode", async () => {
            await macotron.shell.run("osascript", ["-e",
                'tell app "System Events" to tell appearance preferences to set dark mode to not dark mode'
            ]);
        });
        ```
        """)

        // Section 4: Current snippet inventory
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
        parts.append(inventoryText)

        // Section 5: Tool usage instructions
        parts.append("""
        ## Tool Usage

        You have tools to manage snippet files. Use them to fulfill user requests:
        - Use `list_snippets` to see what is currently installed.
        - Use `read_snippet` to inspect existing code before modifying it.
        - Use `write_snippet` to create or update snippets. Always include a descriptive // comment as the first line.
        - Use `delete_snippet` to remove snippets the user no longer wants.
        - Use `read_config` to inspect the user's config.js.

        Every write and delete operation automatically creates a backup, so changes are safe and reversible.
        """)

        return parts.joined(separator: "\n\n")
    }

    /// Load macotron.d.ts from the app bundle.
    private static func loadTypeDefinitions() -> String? {
        // Try main bundle first (for the app target)
        if let url = Bundle.main.url(forResource: "macotron", withExtension: "d.ts") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // Fallback: try finding it relative to the executable
        // This handles cases where the resource might be in a different bundle
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "macotron", withExtension: "d.ts") {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }
        return nil
    }
}
