// LocalProvider.swift — Apple Foundation Models placeholder (macOS 26+)
import Foundation
import os

private let logger = Logger(subsystem: "com.macotron", category: "ai.local")

/// Placeholder for Apple's on-device Foundation Models framework.
/// On macOS 26+ with Apple Silicon, this will use the built-in LLM.
/// For now, it returns a "not available" message.
public final class LocalProvider: AIProvider, @unchecked Sendable {
    public let providerName = "local"

    public init() {}

    public func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String {
        logger.info("Local AI provider called but not yet available")
        throw AIProviderError.notAvailable(
            reason: "Apple Foundation Models requires macOS 26 or later. "
                + "This feature will be enabled automatically when running on a supported system."
        )
    }

    public func stream(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        logger.info("Local AI streaming called but not yet available")
        throw AIProviderError.notAvailable(
            reason: "Apple Foundation Models requires macOS 26 or later. "
                + "This feature will be enabled automatically when running on a supported system."
        )
    }
}
