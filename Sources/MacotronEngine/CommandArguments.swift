import Foundation

public struct CommandArgumentChoice: Sendable, Equatable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

public enum CommandArgDefault: Sendable, Equatable {
    case none
    case string(String)
    case number(Double)
    case bool(Bool)
}

public struct CommandArgumentSpec: Sendable {
    public let name: String
    public let type: String
    public let placeholder: String
    public let required: Bool
    public let defaultValue: CommandArgDefault
    public let choices: [CommandArgumentChoice]

    public init(
        name: String,
        type: String,
        placeholder: String,
        required: Bool = false,
        defaultValue: CommandArgDefault = .none,
        choices: [CommandArgumentChoice] = []
    ) {
        self.name = name
        self.type = type
        self.placeholder = placeholder
        self.required = required
        self.defaultValue = defaultValue
        self.choices = choices
    }

    public static func parseList(_ raw: Any?) -> [CommandArgumentSpec] {
        guard let items = raw as? [Any] else { return [] }
        var result: [CommandArgumentSpec] = []
        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            guard let name = dict["name"] as? String, !name.isEmpty else { continue }
            var type = (dict["type"] as? String)?.lowercased() ?? "text"
            if type != "text" && type != "number" && type != "dropdown" {
                type = "text"
            }
            let placeholder = (dict["placeholder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            let required = dict["required"] as? Bool ?? false
            let defaultValue = parseDefault(dict["default"])
            var choices: [CommandArgumentChoice] = []
            if type == "dropdown" {
                choices = parseChoices(dict["choices"])
                if choices.isEmpty {
                    NSLog("[Macotron] command argument '%@' dropdown has no choices — skipped", name)
                    continue
                }
            }
            result.append(CommandArgumentSpec(
                name: name,
                type: type,
                placeholder: placeholder,
                required: required,
                defaultValue: defaultValue,
                choices: choices
            ))
        }
        return result
    }

    private static func parseDefault(_ raw: Any?) -> CommandArgDefault {
        switch raw {
        case let s as String: return .string(s)
        case let i as Int: return .number(Double(i))
        case let i as Int32: return .number(Double(i))
        case let d as Double: return .number(d)
        case let b as Bool: return .bool(b)
        default: return .none
        }
    }

    private static func parseChoices(_ raw: Any?) -> [CommandArgumentChoice] {
        guard let items = raw as? [Any] else { return [] }
        var result: [CommandArgumentChoice] = []
        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            guard let value = dict["value"] as? String, !value.isEmpty else { continue }
            let title = (dict["title"] as? String) ?? (dict["label"] as? String) ?? value
            result.append(CommandArgumentChoice(title: title, value: value))
        }
        return result
    }
}

public enum CommandArgumentResolver {
    public enum Failure: Error, Equatable {
        case missingRequired(String)
        case invalidNumber(String)
        case invalidChoice(String)
    }

    public static func resolve(
        specs: [CommandArgumentSpec],
        raw: [String: String]
    ) -> Result<[String: Any], Failure> {
        var values: [String: Any] = [:]
        for spec in specs {
            let trimmed = (raw[spec.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch spec.type {
            case "number":
                if trimmed.isEmpty {
                    if case .number(let n) = spec.defaultValue {
                        values[spec.name] = intOrDouble(n)
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    }
                } else if let n = Double(trimmed) {
                    values[spec.name] = intOrDouble(n)
                } else {
                    return .failure(.invalidNumber(spec.name))
                }
            case "dropdown":
                let value: String
                if trimmed.isEmpty {
                    if case .string(let d) = spec.defaultValue {
                        value = d
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    } else {
                        continue
                    }
                } else {
                    value = trimmed
                }
                if !spec.choices.contains(where: { $0.value == value }) {
                    return .failure(.invalidChoice(spec.name))
                }
                values[spec.name] = value
            default:
                if trimmed.isEmpty {
                    if case .string(let d) = spec.defaultValue {
                        values[spec.name] = d
                    } else if spec.required {
                        return .failure(.missingRequired(spec.name))
                    } else {
                        values[spec.name] = ""
                    }
                } else {
                    values[spec.name] = trimmed
                }
            }
        }
        return .success(values)
    }

    private static func intOrDouble(_ n: Double) -> Any {
        if n.rounded() == n, let i = Int(exactly: n) { return i }
        return n
    }
}
