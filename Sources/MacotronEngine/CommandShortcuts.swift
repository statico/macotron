import Foundation

public struct CommandShortcuts: Equatable, Sendable {
    /// Stored when the user clears a plugin hotkey so it does not fall back to the default.
    public static let unbound = "none"

    public private(set) var bindings: [String: String]

    public init(bindings: [String: String] = [:]) {
        self.bindings = bindings
    }

    public mutating func assign(commandId: String, combo: String) {
        let normalized = combo.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty {
            bindings.removeValue(forKey: commandId)
            return
        }
        removeCombo(normalized)
        bindings[commandId] = normalized
    }

    /// Combos are unique, so assigning one steals it from any other id. The
    /// unbound marker is not a combo: every cleared id keeps its own.
    public mutating func removeCombo(_ combo: String) {
        let normalized = combo.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, normalized != Self.unbound else { return }
        bindings = bindings.filter { $0.value != normalized }
    }

    public func combo(for commandId: String) -> String {
        bindings[commandId] ?? ""
    }

    public func resolved(_ id: String, default defaultCombo: String) -> String {
        guard let stored = bindings[id] else { return defaultCombo }
        return stored == Self.unbound ? "" : stored
    }

    public static func load(from object: Any?) -> CommandShortcuts {
        guard let dict = object as? [String: Any] else { return CommandShortcuts() }
        var bindings: [String: String] = [:]
        for (id, value) in dict {
            guard let combo = value as? String else { continue }
            let normalized = combo.lowercased().trimmingCharacters(in: .whitespaces)
            if !normalized.isEmpty {
                bindings[id] = normalized
            }
        }
        return CommandShortcuts(bindings: bindings)
    }

    public func jsonObject() -> [String: String] {
        bindings
    }
}
