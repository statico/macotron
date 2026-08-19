#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

public final class LocalProvider: AIProvider, @unchecked Sendable {
    public let providerName = "local"

    public init() {}

    public func chat(messages: [AIChatMessage], options: AIRequestOptions) async throws -> String {
        try await generate(messages: messages, options: options, onChunk: nil)
    }

    public func stream(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await generate(messages: messages, options: options, onChunk: onChunk)
    }

    private func generate(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        if #available(macOS 26.0, *) {
            #if canImport(FoundationModels)
            return try await FoundationChat.run(messages: messages, options: options, onChunk: onChunk)
            #endif
        }
        throw AIProviderError.notAvailable(
            reason: "Apple Foundation Models requires macOS 26 or later."
        )
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationChat {
    static func run(
        messages: [AIChatMessage],
        options: AIRequestOptions,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw AIProviderError.notAvailable(reason: unavailableReason(model.availability))
        }
        let normalized = try AIChatMessages.normalize(messages)
        let history = normalized.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        var instructions = options.systemPrompt ?? ""
        if !history.isEmpty {
            if !instructions.isEmpty { instructions += "\n\n" }
            instructions += history
        }
        let prompt = normalized.last?.content ?? ""
        let session = LanguageModelSession(
            model: model,
            instructions: instructions.isEmpty ? nil : instructions
        )
        if let onChunk {
            var last = ""
            for try await snapshot in session.streamResponse(to: prompt) {
                let text = snapshot.content
                if text.count > last.count {
                    onChunk(String(text.dropFirst(last.count)))
                }
                last = text
            }
            return last
        }
        return try await session.respond(to: prompt).content
    }

    static func unavailableReason(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "On-device model is unavailable."
        case .unavailable(.deviceNotEligible):
            return "This Mac cannot run Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "On-device model is unavailable."
        }
    }
}
#endif
