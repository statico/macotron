import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "ai.gemini")

public final class GeminiProvider: AIProvider, @unchecked Sendable {
    public let providerName = "gemini"

    private let apiKey: String?
    private let defaultModel: String
    private let baseURL: String

    public init(apiKey: String? = nil, model: String? = nil, baseURL: String? = nil) {
        self.apiKey = apiKey
        self.defaultModel = model ?? "gemini-2.5-flash"
        self.baseURL = baseURL ?? "https://generativelanguage.googleapis.com"
    }

    public func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String {
        let (data, status) = try await post(messages: messages, options: options)
        guard status == 200 else {
            throw AIProviderError.httpError(
                statusCode: status,
                message: String(data: data, encoding: .utf8) ?? "Unknown error"
            )
        }
        guard let text = GeminiAPI.text(from: data) else {
            throw AIProviderError.invalidResponse
        }
        return text
    }

    public func stream(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw AIProviderError.missingAPIKey }
        let model = options.model ?? defaultModel
        let url = URL(string: "\(baseURL)/v1beta/models/\(model):streamGenerateContent?alt=sse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try GeminiAPI.body(messages: messages, options: options)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw AIProviderError.networkError(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard http.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            throw AIProviderError.httpError(
                statusCode: http.statusCode,
                message: String(data: errorData, encoding: .utf8) ?? "Unknown error"
            )
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr == "[DONE]" { break }
            guard let data = jsonStr.data(using: .utf8),
                  let text = GeminiAPI.text(from: data), !text.isEmpty else { continue }
            full += text
            onChunk(text)
        }
        return full
    }

    private func post(messages: [AIChatMessage], options: AIRequestOptions) async throws -> (Data, Int) {
        guard let key = apiKey, !key.isEmpty else { throw AIProviderError.missingAPIKey }
        let model = options.model ?? defaultModel
        let url = URL(string: "\(baseURL)/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try GeminiAPI.body(messages: messages, options: options)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIProviderError.networkError(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        if http.statusCode != 200 {
            logger.error("Gemini API error \(http.statusCode)")
        }
        return (data, http.statusCode)
    }
}

enum GeminiAPI {
    static func body(messages: [AIChatMessage], options: AIRequestOptions) throws -> Data {
        let normalized = try AIChatMessages.normalize(messages)
        var payload: [String: Any] = [
            "contents": normalized.map { msg -> [String: Any] in
                [
                    "role": msg.role == "assistant" ? "model" : "user",
                    "parts": [["text": msg.content]],
                ]
            },
            "generationConfig": [
                "temperature": options.temperature,
                "maxOutputTokens": options.maxTokens,
            ] as [String: Any],
        ]
        if let system = options.systemPrompt, !system.isEmpty {
            payload["systemInstruction"] = ["parts": [["text": system]]]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func text(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        let texts = parts.compactMap { $0["text"] as? String }
        return texts.isEmpty ? nil : texts.joined()
    }
}
