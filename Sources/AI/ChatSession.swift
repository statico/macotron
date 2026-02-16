// ChatSession.swift — Orchestrates AI conversation with tool-call loop
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.chat")

/// Orchestrates a multi-turn AI conversation, handling tool calls for module management.
///
/// Flow:
/// 1. User message is sent to Claude with system prompt and tool definitions
/// 2. If Claude responds with tool_use, execute the tools via AIToolDefinition
/// 3. Send tool results back to Claude
/// 4. Repeat until Claude gives a final text response (stop_reason == "end_turn")
@MainActor
public final class ChatSession {
    private let provider: ClaudeProvider
    private let moduleManager: ModuleManager

    /// Maximum number of tool-call round trips before forcing a stop
    private let maxToolRounds = 10

    public init(provider: ClaudeProvider, moduleManager: ModuleManager) {
        self.provider = provider
        self.moduleManager = moduleManager
    }

    /// Process a user message through the AI, handling any tool calls in a loop.
    /// Returns the AI's final text response.
    ///
    /// - Parameter userMessage: The natural language message from the user
    /// - Returns: The AI's final text response after all tool calls are resolved
    public func processMessage(_ userMessage: String) async throws -> String {
        // Build fresh system prompt each time (module list may have changed)
        let systemPrompt = AISystemPrompt.build(moduleManager: moduleManager)

        let options = AIRequestOptions(
            maxTokens: 4096,
            temperature: 0.3,
            systemPrompt: systemPrompt
        )

        // Start the conversation with the user message
        var messages: [[String: Any]] = [
            ["role": "user", "content": userMessage]
        ]

        var roundCount = 0

        while roundCount < maxToolRounds {
            roundCount += 1
            logger.info("Chat round \(roundCount): sending \(messages.count) messages")

            // Deep-copy messages and tools for sending across isolation boundary.
            // JSONSerialization round-trip produces a fresh, unshared copy.
            // nonisolated(unsafe) is safe here because the copies are freshly created
            // and will not be accessed from the main actor while in use by the provider.
            nonisolated(unsafe) let messagesCopy = deepCopyJSON(messages) as! [[String: Any]]
            nonisolated(unsafe) let toolsCopy = deepCopyJSON(AIToolDefinition.tools) as! [[String: Any]]

            // Send to Claude with tools
            let response = try await provider.chatWithTools(
                messages: messagesCopy,
                tools: toolsCopy,
                options: options
            )

            // If no tool calls, return the text response
            if response.toolCalls.isEmpty || response.stopReason == "end_turn" {
                let finalText = response.text.isEmpty ? "(No response)" : response.text
                logger.info("Chat complete after \(roundCount) round(s)")
                return finalText
            }

            // There are tool calls to process
            logger.info("Processing \(response.toolCalls.count) tool call(s)")

            // Add the assistant's response (with tool_use blocks) to the conversation
            // We need to reconstruct the content blocks for the messages array
            var assistantContent: [[String: Any]] = []

            // Include any text blocks
            if !response.text.isEmpty {
                assistantContent.append([
                    "type": "text",
                    "text": response.text
                ])
            }

            // Include tool_use blocks
            for toolCall in response.toolCalls {
                assistantContent.append([
                    "type": "tool_use",
                    "id": toolCall.id,
                    "name": toolCall.name,
                    "input": toolCall.input
                ])
            }

            messages.append([
                "role": "assistant",
                "content": assistantContent
            ])

            // Execute each tool and collect results
            var toolResults: [[String: Any]] = []

            for toolCall in response.toolCalls {
                logger.info("Executing tool: \(toolCall.name)")
                let result = AIToolDefinition.execute(
                    toolName: toolCall.name,
                    input: toolCall.input,
                    moduleManager: moduleManager
                )
                logger.info("Tool \(toolCall.name) result: \(result.prefix(200))")

                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolCall.id,
                    "content": result
                ])
            }

            // Send tool results back as a user message
            messages.append([
                "role": "user",
                "content": toolResults
            ])
        }

        // If we hit the max rounds, return whatever text we got plus a note
        logger.warning("Hit maximum tool rounds (\(self.maxToolRounds))")
        return "I completed several operations but hit the maximum number of steps. Please check the results and let me know if you need anything else."
    }

    /// Deep-copy a JSON-compatible value via serialization round-trip.
    /// This produces a fresh, unshared copy that can safely cross isolation boundaries.
    private func deepCopyJSON(_ value: Any) -> Any {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let copy = try? JSONSerialization.jsonObject(with: data) else {
            return value
        }
        return copy
    }
}
