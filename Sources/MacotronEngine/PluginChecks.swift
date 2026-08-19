import Foundation

/// One row from `macotron.checks([{ title, ok, message }])`.
public struct PluginCheck: Equatable, Sendable {
    public let title: String
    public let ok: Bool
    public let message: String

    public init(title: String, ok: Bool, message: String) {
        self.title = title
        self.ok = ok
        self.message = message
    }

    /// Parse a JS array of `{ title, ok, message }`. Rows without a title are dropped.
    /// Missing `ok` is treated as failed.
    public static func parseList(_ value: Any?) -> [PluginCheck] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let dict = row as? [String: Any] else { return nil }
            let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let message = dict["message"] as? String ?? ""
            return PluginCheck(title: title, ok: boolish(dict["ok"]), message: message)
        }
    }

    private static func boolish(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        if let d = value as? Double { return d != 0 }
        return false
    }
}
