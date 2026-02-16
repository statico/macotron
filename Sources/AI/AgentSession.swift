// AgentSession.swift — Core agent loop: plan → execute → validate → repair → done
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.agent")

/// Progress updates emitted by the agent during execution
public enum AgentProgress: Sendable {
    case planning(String)
    case writing(String)
    case testing
    case repairing(Int)
    case done(success: Bool, summary: String)
}

/// Result of an agent run
public struct AgentResult: Sendable {
    public let success: Bool
    public let summary: String
    public let filesCreated: [String]
    public let filesModified: [String]
    public let filesDeleted: [String]
    public let error: String?

    public init(
        success: Bool, summary: String,
        filesCreated: [String] = [], filesModified: [String] = [], filesDeleted: [String] = [],
        error: String? = nil
    ) {
        self.success = success
        self.summary = summary
        self.filesCreated = filesCreated
        self.filesModified = filesModified
        self.filesDeleted = filesDeleted
        self.error = error
    }
}

/// Orchestrates the autonomous agent loop. Given a user command, the agent plans,
/// writes scripts via tool calls, validates them, and auto-repairs on failure.
@MainActor
public final class AgentSession {
    private let provider: ClaudeProvider
    private let snippetManager: SnippetManager

    /// Maximum tool-call rounds before stopping
    private let maxRounds = 15
    /// Maximum repair attempts after validation failure
    private let maxRepairAttempts = 2

    /// Called on each progress update. Set by the caller before `run()`.
    public var onProgress: ((AgentProgress) -> Void)?

    public init(provider: ClaudeProvider, snippetManager: SnippetManager) {
        self.provider = provider
        self.snippetManager = snippetManager
    }

    /// Run the agent loop for a user command.
    /// - Parameter command: The natural language command from the user
    /// - Returns: The result of the agent's work
    public func run(command: String) async throws -> AgentResult {
        onProgress?(.planning(command))

        let systemPrompt = AISystemPrompt.buildAgentPrompt(snippetManager: snippetManager)
        let options = AIRequestOptions(
            maxTokens: 4096,
            temperature: 0.3,
            systemPrompt: systemPrompt
        )

        // Track file changes by snapshotting before/after
        let snippetsBefore = Set(snippetManager.listSnippets(directory: "snippets").map(\.filename))
        let commandsBefore = Set(snippetManager.listSnippets(directory: "commands").map(\.filename))

        var messages: [[String: Any]] = [
            ["role": "user", "content": command]
        ]

        var roundCount = 0
        var repairAttempts = 0
        var lastText = ""

        while roundCount < maxRounds {
            try Task.checkCancellation()
            roundCount += 1
            logger.info("Agent round \(roundCount): sending \(messages.count) messages")

            // Deep-copy for isolation boundary
            nonisolated(unsafe) let messagesCopy = deepCopyJSON(messages) as! [[String: Any]]
            nonisolated(unsafe) let toolsCopy = deepCopyJSON(AIToolDefinition.tools) as! [[String: Any]]

            let response: ClaudeProvider.ToolChatResponse
            do {
                response = try await provider.chatWithTools(
                    messages: messagesCopy,
                    tools: toolsCopy,
                    options: options
                )
            } catch {
                let msg = "AI request failed: \(error.localizedDescription)"
                onProgress?(.done(success: false, summary: msg))
                return AgentResult(success: false, summary: msg, error: msg)
            }

            lastText = response.text

            // No tool calls — agent is done
            if response.toolCalls.isEmpty || response.stopReason == "end_turn" {
                break
            }

            // Process tool calls
            var assistantContent: [[String: Any]] = []
            if !response.text.isEmpty {
                assistantContent.append(["type": "text", "text": response.text])
            }

            for toolCall in response.toolCalls {
                assistantContent.append([
                    "type": "tool_use",
                    "id": toolCall.id,
                    "name": toolCall.name,
                    "input": toolCall.input
                ])
            }

            messages.append(["role": "assistant", "content": assistantContent])

            // Execute tools and emit progress
            var toolResults: [[String: Any]] = []

            for toolCall in response.toolCalls {
                emitToolProgress(toolCall)

                logger.info("Agent executing tool: \(toolCall.name)")
                let result = AIToolDefinition.execute(
                    toolName: toolCall.name,
                    input: toolCall.input,
                    snippetManager: snippetManager
                )
                logger.info("Agent tool \(toolCall.name) result: \(result.prefix(200))")

                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolCall.id,
                    "content": result
                ])
            }

            // Check for reload errors after tool execution
            let errors = snippetManager.lastReloadErrors
            if !errors.isEmpty {
                onProgress?(.testing)

                if repairAttempts < maxRepairAttempts {
                    repairAttempts += 1
                    onProgress?(.repairing(repairAttempts))

                    // Inject failure trace as part of tool results
                    if let trace = AISystemPrompt.formatFailureTrace(errors: errors) {
                        var toolResultsWithErrors = toolResults
                        // Add error context to the last tool result
                        toolResultsWithErrors.append([
                            "type": "tool_result",
                            "tool_use_id": "error_trace",
                            "content": trace
                        ])
                        // Actually, we need to send errors as a separate user message
                        messages.append(["role": "user", "content": toolResults])
                        messages.append(["role": "user", "content": trace])

                        // Break repetition on second repair attempt
                        if repairAttempts == maxRepairAttempts {
                            messages.append(["role": "user", "content":
                                "This is your last repair attempt. Try a DIFFERENT approach."
                            ])
                        }
                        continue
                    }
                }

                // Exhausted repair attempts
                let errorSummary = errors.map { "\($0.filename): \($0.error)" }.joined(separator: "; ")
                let msg = "Scripts have errors after \(repairAttempts) repair attempts: \(errorSummary)"
                onProgress?(.done(success: false, summary: msg))
                return buildResult(
                    success: false, summary: msg,
                    snippetsBefore: snippetsBefore, commandsBefore: commandsBefore,
                    error: msg
                )
            }

            // No errors — send tool results and continue
            messages.append(["role": "user", "content": toolResults])
        }

        // Success
        let summary = lastText.isEmpty ? "Done" : lastText
        onProgress?(.done(success: true, summary: summary))
        return buildResult(
            success: true, summary: summary,
            snippetsBefore: snippetsBefore, commandsBefore: commandsBefore
        )
    }

    // MARK: - Helpers

    private func emitToolProgress(_ toolCall: ClaudeProvider.ToolChatResponse.ToolCall) {
        switch toolCall.name {
        case "write_snippet":
            let filename = toolCall.input["filename"] as? String ?? "script"
            onProgress?(.writing(filename))
        case "write_config":
            onProgress?(.writing("config.js"))
        case "delete_snippet":
            let filename = toolCall.input["filename"] as? String ?? "script"
            onProgress?(.writing(filename))
        default:
            break
        }
    }

    private func buildResult(
        success: Bool, summary: String,
        snippetsBefore: Set<String>, commandsBefore: Set<String>,
        error: String? = nil
    ) -> AgentResult {
        let snippetsAfter = Set(snippetManager.listSnippets(directory: "snippets").map(\.filename))
        let commandsAfter = Set(snippetManager.listSnippets(directory: "commands").map(\.filename))

        let allBefore = snippetsBefore.union(commandsBefore)
        let allAfter = snippetsAfter.union(commandsAfter)

        let created = Array(allAfter.subtracting(allBefore)).sorted()
        let deleted = Array(allBefore.subtracting(allAfter)).sorted()
        let modified = Array(allAfter.intersection(allBefore)).sorted() // Simplified — could diff content

        return AgentResult(
            success: success,
            summary: summary,
            filesCreated: created,
            filesModified: modified,
            filesDeleted: deleted,
            error: error
        )
    }

    private func deepCopyJSON(_ value: Any) -> Any {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let copy = try? JSONSerialization.jsonObject(with: data) else {
            return value
        }
        return copy
    }
}
