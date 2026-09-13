// PluginNeeds.swift — Parse // @macotron needs <semver> and compare to host API
import Foundation

public struct SemVer: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse `1`, `1.2`, or `1.2.3`. Missing minor/patch become 0.
    public init?(_ string: String) {
        let fields = string.split(separator: ".", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Int($0) }
        guard (1...3).contains(fields.count), parts.count == fields.count,
              parts.allSatisfy({ $0 >= 0 }) else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Compact display: drop trailing `.0` patch (e.g. `1.2`).
    public var shortDescription: String {
        patch == 0 ? "\(major).\(minor)" : description
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct PluginNeedsError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

public enum PluginNeeds {
    private static let scanLineLimit = 20
    private static let pragmaPrefix = "@macotron needs "

    /// Parse `// @macotron needs <semver>` from the first ~20 lines.
    /// Missing pragma → `1.0.0`. Invalid pragma → `.failure`.
    public static func parse(_ source: String) -> Result<SemVer, PluginNeedsError> {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).prefix(scanLineLimit)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }
            var body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard body.hasPrefix(pragmaPrefix) else { continue }
            body = body.dropFirst(pragmaPrefix.count).trimmingCharacters(in: .whitespaces)
            let token = body.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            guard let version = SemVer(token) else {
                return .failure(PluginNeedsError(
                    "Invalid @macotron needs pragma: \(token.isEmpty ? "(empty)" : token)"
                ))
            }
            return .success(version)
        }
        return .success(SemVer(major: 1, minor: 0, patch: 0))
    }

    public static func unmetMessage(needs: SemVer, host: SemVer) -> String {
        "Needs Macotron API \(needs.shortDescription) (this host is \(host.shortDescription))"
    }
}
