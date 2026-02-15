// OpenAIProvider.swift — OpenAI API implementation (GPT-4, etc.)
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.openai")

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

    // MARK: - Key Validation

    /// Validate an OpenAI API key by listing models and checking for the preferred model.
    public static func validateKey(_ key: String) async -> AIKeyValidationResult {
        let preferredModel = "gpt-4o"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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

    // MARK: - Chat

    public func chat(prompt: String, options: AIRequestOptions) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let model = options.model ?? defaultModel

        var messages: [[String: Any]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "messages": messages,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
            logger.error("OpenAI API error \(httpResponse.statusCode): \(errorBody)")
            throw AIProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return content
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

        var messages: [[String: Any]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "stream": true,
            "messages": messages,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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

        var fullResponse = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }

            guard let lineData = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullResponse += content
            onChunk(content)
        }

        return fullResponse
    }
}
