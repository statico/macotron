// ClaudeProvider.swift — Anthropic Claude API implementation
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.claude")

public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let providerName = "claude"

    private let apiKey: String?
    private let defaultModel: String
    private let baseURL: String

    public init(
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil
    ) {
        self.apiKey = apiKey
        self.defaultModel = model ?? "claude-opus-4-6"
        self.baseURL = baseURL ?? "https://api.anthropic.com"
    }

    public func chat(prompt: String, options: AIRequestOptions) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let model = options.model ?? defaultModel

        // Build the request body
        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        if options.temperature >= 0 {
            body["temperature"] = options.temperature
        }

        if let systemPrompt = options.systemPrompt {
            body["system"] = systemPrompt
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIProviderError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Claude API error \(httpResponse.statusCode): \(errorBody)")
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    public func stream(
        prompt: String,
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let model = options.model ?? defaultModel

        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        if options.temperature >= 0 {
            body["temperature"] = options.temperature
        }

        if let systemPrompt = options.systemPrompt {
            body["system"] = systemPrompt
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw AIProviderError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Collect the error body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        // Parse SSE stream
        var fullResponse = ""
        for try await line in bytes.lines {
            // SSE format: "data: {...}"
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))

            // [DONE] signals end of stream (Anthropic uses message_stop event)
            if jsonStr == "[DONE]" { break }

            guard let lineData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let eventType = event["type"] as? String

            // content_block_delta contains the text chunks
            if eventType == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullResponse += text
                onChunk(text)
            }
        }

        return fullResponse
    }

    // MARK: - Key Validation

    /// Validate an Anthropic API key by listing models and checking for the preferred model.
    public static func validateKey(_ key: String) async -> AIKeyValidationResult {
        let preferredModel = "claude-opus-4-6"
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .networkError(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .networkError(message: "Invalid response")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            return .invalidKey(message: "Invalid API key (HTTP \(httpResponse.statusCode))")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            return .invalidKey(message: "HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse model list
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else {
            return .networkError(message: "Could not parse models response")
        }

        let modelIDs = modelsArray.compactMap { $0["id"] as? String }

        if modelIDs.contains(preferredModel) {
            return .valid(models: modelIDs)
        } else {
            return .modelUnavailable(available: modelIDs)
        }
    }

    // MARK: - Tool Use Chat

    /// Response from a single Claude API call that may contain text and/or tool use blocks.
    /// Uses @unchecked Sendable because contentBlocks and ToolCall.input contain [String: Any],
    /// which only holds JSON-safe values (String, Number, Bool, Array, Dictionary, NSNull).
    public struct ToolChatResponse: @unchecked Sendable {
        /// The stop reason: "end_turn", "tool_use", "max_tokens", etc.
        public let stopReason: String
        /// All content blocks from the response (text and tool_use mixed)
        public let contentBlocks: [[String: Any]]
        /// Extracted text from all text blocks, concatenated
        public let text: String
        /// Extracted tool use calls (id, name, input)
        public let toolCalls: [ToolCall]

        public struct ToolCall: @unchecked Sendable {
            public let id: String
            public let name: String
            public let input: [String: Any]

            public init(id: String, name: String, input: [String: Any]) {
                self.id = id
                self.name = name
                self.input = input
            }
        }

        public init(stopReason: String, contentBlocks: [[String: Any]], text: String, toolCalls: [ToolCall]) {
            self.stopReason = stopReason
            self.contentBlocks = contentBlocks
            self.text = text
            self.toolCalls = toolCalls
        }
    }

    /// Send a chat request with tool definitions, supporting the full Claude tool use protocol.
    /// Returns a `ToolChatResponse` with parsed text and tool calls.
    ///
    /// - Parameters:
    ///   - messages: The conversation messages array (role + content)
    ///   - tools: Tool definitions in Claude API format
    ///   - options: Request options (model, maxTokens, temperature, systemPrompt)
    /// - Returns: Parsed response with stop reason, text, and tool calls
    public func chatWithTools(
        messages: [[String: Any]],
        tools: [[String: Any]],
        options: AIRequestOptions
    ) async throws -> ToolChatResponse {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let model = options.model ?? defaultModel

        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "messages": messages,
            "tools": tools,
        ]

        if options.temperature >= 0 {
            body["temperature"] = options.temperature
        }

        if let systemPrompt = options.systemPrompt {
            body["system"] = systemPrompt
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIProviderError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Claude API error \(httpResponse.statusCode): \(errorBody)")
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        // Parse the full response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let stopReason = json["stop_reason"] as? String else {
            throw AIProviderError.invalidResponse
        }

        // Extract text blocks and tool_use blocks
        var textParts: [String] = []
        var toolCalls: [ToolChatResponse.ToolCall] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    textParts.append(text)
                }
            case "tool_use":
                if let id = block["id"] as? String,
                   let name = block["name"] as? String,
                   let input = block["input"] as? [String: Any] {
                    toolCalls.append(ToolChatResponse.ToolCall(id: id, name: name, input: input))
                }
            default:
                break
            }
        }

        return ToolChatResponse(
            stopReason: stopReason,
            contentBlocks: content,
            text: textParts.joined(separator: "\n"),
            toolCalls: toolCalls
        )
    }
}
