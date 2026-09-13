// AIProvider.swift — Protocol and factory for AI provider backends
import Foundation

/// Options passed to AI providers for chat/stream requests
public struct AIRequestOptions: Sendable {
    public let model: String?
    public let maxTokens: Int
    public let temperature: Double
    public let systemPrompt: String?

    public init(
        model: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double = 0.7,
        systemPrompt: String? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.systemPrompt = systemPrompt
    }
}

public struct AIChatMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: content)
    }
}

public enum AIChatMessageError: Error, Equatable, LocalizedError {
    case invalidRole(String)
    case emptyContent
    case emptyMessages

    public var errorDescription: String? {
        switch self {
        case .invalidRole(let role): return "Invalid message role: \(role)"
        case .emptyContent: return "Message content must not be empty"
        case .emptyMessages: return "messages must not be empty"
        }
    }
}

public enum AIChatMessages {
    public static func normalize(_ messages: [AIChatMessage]) throws -> [AIChatMessage] {
        guard !messages.isEmpty else { throw AIChatMessageError.emptyMessages }
        var out: [AIChatMessage] = []
        out.reserveCapacity(messages.count)
        for message in messages {
            let role = message.role.lowercased()
            guard role == "user" || role == "assistant" else {
                throw AIChatMessageError.invalidRole(message.role)
            }
            guard !message.content.isEmpty else {
                throw AIChatMessageError.emptyContent
            }
            out.append(AIChatMessage(role: role, content: message.content))
        }
        return out
    }
}

/// One SSE round trip for the HTTP providers: send `request`, fail the same way
/// on a non-200, then feed every `data:` payload to `delta` and accumulate what
/// it returns. `delta` returns nil for an event that carries no text.
func streamSSE(
    _ request: URLRequest,
    onChunk: @escaping @Sendable (String) -> Void,
    delta: ([String: Any]) -> String?
) async throws -> String {
    let bytes: URLSession.AsyncBytes
    let response: URLResponse
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
        let payload = String(line.dropFirst(6))
        if payload == "[DONE]" { break }
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = delta(event), !text.isEmpty else { continue }
        full += text
        onChunk(text)
    }
    return full
}

/// Protocol all AI providers must conform to
public protocol AIProvider: AnyObject, Sendable {
    /// The provider name (e.g. "claude", "openai", "gemini", "local")
    var providerName: String { get }

    /// Send a chat message and receive the full response
    func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String

    /// Stream a chat response, calling onChunk for each piece, returning the full result
    func stream(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

/// Errors that AI providers can throw
public enum AIProviderError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case notAvailable(reason: String)
    case networkError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not provided. Set it in your config."
        case .invalidResponse:
            return "Received an invalid response from the API."
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .notAvailable(let reason):
            return "Provider not available: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

