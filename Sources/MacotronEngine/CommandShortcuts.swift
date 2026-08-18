import Foundation

public struct CommandShortcuts: Equatable, Sendable {
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
        bindings = bindings.filter { $0.value != normalized }
        bindings[commandId] = normalized
    }

    public func combo(for commandId: String) -> String {
        bindings[commandId] ?? ""
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
