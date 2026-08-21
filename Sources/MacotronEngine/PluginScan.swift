import Foundation

public struct PluginScanChunk: Equatable, Sendable {
    public let index: Int
    public let text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}

public struct PluginScanFinding: Equatable, Sendable {
    public let pass: Int
    public let message: String

    public init(pass: Int, message: String) {
        self.pass = pass
        self.message = message
    }
}

public struct PluginScanReport: Equatable, Sendable {
    public var modelAvailable: Bool
    public var unavailableReason: String?
    public var findings: [PluginScanFinding]
    public var staticFlags: [String]

    public init(
        modelAvailable: Bool = true,
        unavailableReason: String? = nil,
        findings: [PluginScanFinding] = [],
        staticFlags: [String] = []
    ) {
        self.modelAvailable = modelAvailable
        self.unavailableReason = unavailableReason
        self.findings = findings
        self.staticFlags = staticFlags
    }

    public var approved: Bool {
        modelAvailable && findings.isEmpty && staticFlags.isEmpty
    }

    public var needsOverride: Bool { !approved }
}

public enum PluginScan {
    public static let passCount = 3
    /// On-device context is ~4096 tokens. Leave room for instructions.
    public static let defaultMaxChars = 6000
    public static let overlapChars = 400

    public static func chunks(_ source: String, maxChars: Int = defaultMaxChars, overlap: Int = overlapChars) -> [PluginScanChunk] {
        let chars = Array(source)
        guard chars.count > maxChars else {
            return [PluginScanChunk(index: 0, text: source)]
        }
        var result: [PluginScanChunk] = []
        var start = 0
        var index = 0
        while start < chars.count {
            let end = min(start + maxChars, chars.count)
            result.append(PluginScanChunk(index: index, text: String(chars[start..<end])))
            if end >= chars.count { break }
            start = max(end - overlap, start + 1)
            index += 1
        }
        return result
    }

    public static func staticFlags(_ source: String) -> [String] {
        var flags: [String] = []
        if source.contains("eval(") {
            flags.append("Uses eval()")
        }
        if source.range(of: #"\\x[0-9a-fA-F]{2}"#, options: .regularExpression) != nil,
           source.filter({ $0 == "\\" }).count > 80 {
            flags.append("Large hex-escaped payload")
        }
        if source.contains("atob("), source.count > 2000 {
            flags.append("Decodes a large base64 blob")
        }
        return flags
    }

    public static func failed(anyPassFails reports: [[PluginScanFinding]], staticFlags: [String]) -> PluginScanReport {
        PluginScanReport(findings: reports.flatMap { $0 }, staticFlags: staticFlags)
    }
}
