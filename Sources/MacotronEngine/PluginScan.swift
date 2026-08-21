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
    /// SHA-256 of the bytes the scan actually read. A verdict without it binds to nothing.
    public var sourceHash: String?

    public init(
        modelAvailable: Bool = true,
        unavailableReason: String? = nil,
        findings: [PluginScanFinding] = [],
        staticFlags: [String] = [],
        sourceHash: String? = nil
    ) {
        self.modelAvailable = modelAvailable
        self.unavailableReason = unavailableReason
        self.findings = findings
        self.staticFlags = staticFlags
        self.sourceHash = sourceHash
    }

    public var approved: Bool {
        modelAvailable && findings.isEmpty && staticFlags.isEmpty
    }

    public var needsOverride: Bool { !approved }

    public func matches(source: String) -> Bool {
        sourceHash == PluginHash.sha256(source: source)
    }
}

public enum PluginScan {
    public static let passCount = 3
    /// On-device context is ~4096 tokens. Leave room for instructions.
    public static let defaultMaxChars = 6000
    public static let overlapChars = 400

    public static func chunks(_ source: String, maxChars: Int = defaultMaxChars, overlap: Int = overlapChars) -> [PluginScanChunk] {
        chunks(source, maxTokens: maxChars, overlapTokens: overlap, tokenCount: { $0.count })
    }

    /// Split untrusted source so each slice fits `maxTokens`, with `overlapTokens` shared.
    public static func chunks(
        _ source: String,
        maxTokens: Int,
        overlapTokens: Int,
        tokenCount: (String) -> Int
    ) -> [PluginScanChunk] {
        guard !source.isEmpty else { return [PluginScanChunk(index: 0, text: source)] }
        let budget = max(maxTokens, 1)
        let overlap = min(max(overlapTokens, 0), budget - 1)
        if tokenCount(source) <= budget {
            return [PluginScanChunk(index: 0, text: source)]
        }
        let chars = Array(source)
        var result: [PluginScanChunk] = []
        var start = 0
        var index = 0
        while start < chars.count {
            var lo = start + 1
            var hi = chars.count
            var best = lo
            while lo <= hi {
                let mid = (lo + hi) / 2
                let slice = String(chars[start..<mid])
                if tokenCount(slice) <= budget {
                    best = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            result.append(PluginScanChunk(index: index, text: String(chars[start..<best])))
            if best >= chars.count { break }
            var next = best
            if overlap > 0 {
                var back = best
                var low = start
                while low + 1 < back {
                    let mid = (low + back) / 2
                    let tail = String(chars[mid..<best])
                    if tokenCount(tail) <= overlap {
                        back = mid
                    } else {
                        low = mid
                    }
                }
                next = back
            }
            start = min(max(next, start + 1), chars.count)
            index += 1
        }
        return result
    }

    public static func unavailableReport(reason: String, staticFlags: [String] = []) -> PluginScanReport {
        PluginScanReport(modelAvailable: false, unavailableReason: reason, staticFlags: staticFlags)
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
        if source.contains("macotron.keychain."),
           source.contains("macotron.http.post")
            || source.contains("macotron.http.put")
            || source.contains("macotron.http.delete") {
            flags.append("Sends keychain data over the network")
        }
        let lower = source.lowercased()
        if source.contains("macotron.shell.run"),
           lower.contains("curl") || lower.contains("wget")
            || lower.contains("/bin/sh") || lower.contains("/bin/bash") {
            flags.append("Shell runs a download or interpreter")
        }
        if lower.contains("ignore previous") || lower.contains("ignore all rules")
            || lower.contains("return approved true") {
            flags.append("Prompt-injection comment")
        }
        if source.contains("</UNTRUSTED_PLUGIN_SOURCE>") || source.contains("<UNTRUSTED_PLUGIN_SOURCE>") {
            flags.append("Fake scanner closer tag")
        }
        return flags
    }

    /// Drop model noise: wrapper echoes, context errors, and ordinary host-API lists.
    public static func keepFinding(_ message: String, source: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("exceeded model context") { return false }
        if lower.hasPrefix("scan failed:") { return true }
        if lower.contains("untrusted_plugin_source") || lower.contains("untrusted plugin source") {
            return containsScannerTag(source)
        }
        return citesDanger(trimmed, source: source)
    }

    public static func keepFindings(_ findings: [PluginScanFinding], source: String) -> [PluginScanFinding] {
        findings.filter { keepFinding($0.message, source: source) }
    }

    /// A finding counts only if it names a dangerous API that is actually in the source.
    public static func citesDanger(_ message: String, source: String) -> Bool {
        let hay = source.lowercased()
        let msg = message.lowercased()
        let markers = [
            "eval(", "atob(", "keychain.", "http.post", "http.put", "http.delete",
            "fs.write", "fs.rename",
        ]
        if markers.contains(where: { msg.contains($0) && hay.contains($0) }) {
            return true
        }
        if msg.contains("shell.run"), hay.contains("shell.run") {
            let remote = ["curl", "wget", "/bin/sh", "/bin/bash"]
            if remote.contains(where: { msg.contains($0) && hay.contains($0) }) {
                return true
            }
        }
        if (msg.contains("ignore previous") || msg.contains("ignore rules"))
            && (hay.contains("ignore previous") || hay.contains("ignore rules")) {
            return true
        }
        if (msg.contains("untrusted_plugin_source") || msg.contains("untrusted plugin source")),
           containsScannerTag(source) {
            return true
        }
        return false
    }

    public static func containsScannerTag(_ source: String) -> Bool {
        source.contains("</UNTRUSTED_PLUGIN_SOURCE>") || source.contains("<UNTRUSTED_PLUGIN_SOURCE>")
    }

    public static func failed(anyPassFails reports: [[PluginScanFinding]], staticFlags: [String]) -> PluginScanReport {
        PluginScanReport(findings: reports.flatMap { $0 }, staticFlags: staticFlags)
    }
}
