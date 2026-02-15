// NLClassifier.swift — Classify launcher input as search, command, or natural language
import Foundation

public enum InputClassification {
    case search
    case command
    case naturalLang
}

@MainActor
public final class NLClassifier {
    private var knownCommands: Set<String> = []

    public init() {}

    public func setKnownCommands(_ commands: Set<String>) {
        knownCommands = commands
    }

    public func classify(_ input: String) -> InputClassification {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .search }

        // Exact match against known commands
        if knownCommands.contains(trimmed.lowercased()) { return .command }

        // Explicit chat prefix
        if trimmed.hasPrefix(">") { return .naturalLang }

        // Single word or looks like a filename → search
        if !trimmed.contains(" ") { return .search }
        if trimmed.hasSuffix(".js") || trimmed.hasSuffix(".app") { return .search }

        // Starts with a verb → natural language
        let firstWord = trimmed.split(separator: " ").first?.lowercased() ?? ""
        let actionVerbs: Set<String> = [
            "set", "add", "create", "make", "open", "show", "hide", "move",
            "resize", "tile", "warn", "notify", "watch", "monitor", "start",
            "stop", "remove", "delete", "change", "update", "fix", "help",
            "tell", "configure", "enable", "disable", "turn", "list", "what",
            "how", "why", "when", "can", "summarize", "describe", "explain"
        ]
        if actionVerbs.contains(firstWord) { return .naturalLang }

        // Question patterns
        let questionPatterns = ["what ", "how ", "why ", "can you", "please ", "i want", "i need"]
        let lower = trimmed.lowercased()
        if questionPatterns.contains(where: { lower.hasPrefix($0) }) { return .naturalLang }

        // 3+ words → probably natural language
        return trimmed.split(separator: " ").count >= 3 ? .naturalLang : .search
    }
}
