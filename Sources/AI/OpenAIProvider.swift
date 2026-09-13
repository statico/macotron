// OpenAIProvider.swift — OpenAI API implementation (GPT-4, etc.)
import Foundation

public final class OpenAIProvider: AIProvider, @unchecked Sendable {
    public let providerName = "openai"

    private let apiKey: String?
    private let defaultModel: String
    private let baseURL: String

    public init(
        apiKey: String? = nil,
        model: String? = nil,
        baseURL: String? = nil
    ) {
        self.apiKey = apiKey
        self.defaultModel = model ?? "gpt-4o"
        self.baseURL = baseURL ?? "https://api.openai.com"
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
        var apiMessages: [[String: Any]] = []
        if let systemPrompt = options.systemPrompt {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }
        apiMessages.append(contentsOf: normalized.map {
            ["role": $0.role, "content": $0.content]
        })

        let body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "stream": true,
            "messages": apiMessages,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        return try await streamSSE(request, onChunk: onChunk) { event in
            guard let choices = event["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        }
    }
}
