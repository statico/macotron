// ClaudeProvider.swift — Anthropic Claude API implementation
import Foundation

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

    public func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String {
        try await stream(messages: messages, options: options, onChunk: { _ in })
    }

    public func stream(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let model = options.model ?? defaultModel
        let normalized = try AIChatMessages.normalize(messages)
        let apiMessages: [[String: Any]] = normalized.map {
            ["role": $0.role, "content": $0.content]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "stream": true,
            "messages": apiMessages
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

        return try await streamSSE(request, onChunk: onChunk) { event in
            // content_block_delta carries the text chunks.
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }
}
