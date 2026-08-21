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

    /// First 8 KB is enough: demos declare `macotron.plugin({ title })` at the top.
    private static let prefixBytes = 8192

    public static func parse(_ source: String) -> Info {
        guard let start = source.range(of: "macotron.plugin(") else {
            return Info(title: nil, description: nil)
        }
        let window = source[start.lowerBound...].prefix(prefixBytes)
        return Info(
            title: stringValue("title", in: window),
            description: stringValue("description", in: window),
            permissions: stringArray("permissions", in: window)
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

    private static func stringValue(_ key: String, in text: Substring) -> String? {
        let pattern = "\(key)\\s*:\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSString(string: String(text))
        guard let match = regex.firstMatch(in: String(text), range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let value = ns.substring(with: match.range(at: 1))
        return value.isEmpty ? nil : value
    }

    private static func stringArray(_ key: String, in text: Substring) -> [String] {
        let pattern = "\(key)\\s*:\\s*\\[([^\\]]*)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let raw = String(text)
        let ns = NSString(string: raw)
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return [] }
        let inner = ns.substring(with: match.range(at: 1))
        let item = try? NSRegularExpression(pattern: "[\"']([^\"']+)[\"']")
        let nsInner = NSString(string: inner)
        let matches = item?.matches(in: inner, range: NSRange(location: 0, length: nsInner.length)) ?? []
        return matches.compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return nsInner.substring(with: m.range(at: 1))
        }
    }
}
