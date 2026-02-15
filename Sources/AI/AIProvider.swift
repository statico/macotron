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

/// Protocol all AI providers must conform to
public protocol AIProvider: AnyObject, Sendable {
    /// The provider name (e.g. "claude", "openai", "gemini", "local")
    var providerName: String { get }

    /// Send a chat message and receive the full response
    func chat(prompt: String, options: AIRequestOptions) async throws -> String

    /// Stream a chat response, calling onChunk for each piece, returning the full result
    func stream(
        prompt: String,
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

/// Factory for creating AI provider instances
public enum AIProviderFactory {
    /// Known provider configuration
    public struct ProviderConfig {
        public let apiKey: String?
        public let model: String?
        public let baseURL: String?

        public init(apiKey: String? = nil, model: String? = nil, baseURL: String? = nil) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
        }
    }

    /// Create a provider by name
    public static func create(name: String, config: ProviderConfig = .init()) -> AIProvider {
        switch name.lowercased() {
        case "claude", "anthropic":
            return ClaudeProvider(apiKey: config.apiKey, model: config.model)
        case "local", "apple":
            return LocalProvider()
        default:
            // Return a placeholder that explains the provider is not yet implemented
            return PlaceholderProvider(name: name)
        }
    }
}

/// A placeholder provider for not-yet-implemented backends
public final class PlaceholderProvider: AIProvider, @unchecked Sendable {
    public let providerName: String

    public init(name: String) {
        self.providerName = name
    }

    public func chat(prompt: String, options: AIRequestOptions) async throws -> String {
        throw AIProviderError.notAvailable(
            reason: "The '\(providerName)' provider is not yet implemented."
        )
    }

    public func stream(
        prompt: String,
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw AIProviderError.notAvailable(
            reason: "The '\(providerName)' provider is not yet implemented."
        )
    }
}
