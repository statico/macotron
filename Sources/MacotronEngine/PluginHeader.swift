// PluginHeader.swift — Read title/description from macotron.plugin() without eval
import Foundation

public enum PluginHeader {
    public struct Info: Equatable, Sendable {
        public var title: String?
        public var description: String?
        public var permissions: [String]

        public init(title: String? = nil, description: String? = nil, permissions: [String] = []) {
            self.title = title
            self.description = description
            self.permissions = permissions
        }
    }

    /// First 8 KB is enough: plugins declare `macotron.plugin({ title })` at the top.
    private static let prefixBytes = 8192

    public static func parse(_ source: String) -> Info {
        guard let start = source.range(of: "macotron.plugin(") else {
            return Info(title: nil, description: nil)
        }
        let window = source[start.lowerBound...].prefix(prefixBytes)
        return Info(
            title: stringValue(/title\s*:\s*["']([^"']*)["']/, in: window),
            description: stringValue(/description\s*:\s*["']([^"']*)["']/, in: window),
            permissions: stringArray(in: window)
        )
    }

    public static func parse(file url: URL) -> Info {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Info(title: nil, description: nil)
        }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: prefixBytes)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            return Info(title: nil, description: nil)
        }
        return parse(text)
    }

    private static func stringValue(_ pattern: Regex<(Substring, Substring)>, in text: Substring) -> String? {
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let value = String(match.output.1)
        return value.isEmpty ? nil : value
    }

    private static func stringArray(in text: Substring) -> [String] {
        guard let match = text.firstMatch(of: /permissions\s*:\s*\[([^\]]*)\]/) else { return [] }
        return match.output.1.matches(of: /["']([^"']+)["']/).map { String($0.output.1) }
    }
}
