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
        self.defaultModel = model ?? "claude-sonnet-4-20250514"
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
}
