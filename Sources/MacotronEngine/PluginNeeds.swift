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
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              let major = Int(parts[0]), major >= 0 else { return nil }
        let minor: Int
        let patch: Int
        switch parts.count {
        case 1:
            minor = 0
            patch = 0
        case 2:
            guard let m = Int(parts[1]), m >= 0 else { return nil }
            minor = m
            patch = 0
        default:
            guard let m = Int(parts[1]), m >= 0,
                  let p = Int(parts[2]), p >= 0 else { return nil }
            minor = m
            patch = p
        }
        self.init(major: major, minor: minor, patch: patch)
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
