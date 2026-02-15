// CapabilityReview.swift — Static analysis of snippet capabilities for security review
import Foundation

public enum CapabilityTier: Int, Comparable, Sendable {
    case safe = 0
    case moderate = 1
    case dangerous = 2

    public static func < (lhs: CapabilityTier, rhs: CapabilityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SnippetManifest: Sendable {
    public let apisUsed: Set<String>
    public let shellCommands: [String]
    public let networkTargets: [String]
    public let fileTargets: [String]
    public let tier: CapabilityTier
}

public enum CapabilityReview {
    private static let apiTiers: [String: CapabilityTier] = [
        // Safe — read-only queries
        "window.getAll": .safe,
        "window.focused": .safe,
        "clipboard.text": .safe,
        "system.cpuTemp": .safe,
        "system.memory": .safe,
        "system.battery": .safe,
        "camera.isActive": .safe,
        "app.list": .safe,
        "spotlight.search": .safe,
        "display.list": .safe,
        "keychain.get": .safe,
        "keychain.has": .safe,

        // Moderate — visible effects, easily reversible
        "window.move": .moderate,
        "window.moveToFraction": .moderate,
        "notify.show": .moderate,
        "menubar.add": .moderate,
        "menubar.update": .moderate,
        "menubar.remove": .moderate,
        "menubar.setTitle": .moderate,
        "menubar.setIcon": .moderate,
        "keyboard.on": .moderate,
        "clipboard.set": .moderate,
        "app.launch": .moderate,
        "app.switch": .moderate,

        // Dangerous — system, network, or files
        "shell.run": .dangerous,
        "fs.write": .dangerous,
        "fs.delete": .dangerous,
        "fs.remove": .dangerous,
        "http.post": .dangerous,
        "http.put": .dangerous,
        "http.delete": .dangerous,
        "url.open": .dangerous,
        "url.registerHandler": .dangerous,
        "keychain.set": .dangerous,
        "keychain.delete": .dangerous,
        "screen.capture": .dangerous,
    ]

    /// Dangerous API patterns for auto-fix gating
    public static let dangerousPatterns: [String] = [
        "shell.run",
        "fs.write", "fs.delete", "fs.remove",
        "http.post", "http.put", "http.delete",
        "keychain.set", "keychain.delete",
        "url.registerHandler",
    ]

    /// Analyze a snippet's source code and extract its capability manifest
    public static func review(_ js: String) -> SnippetManifest {
        var apis = Set<String>()
        var shellCmds: [String] = []
        var networkURLs: [String] = []
        var filePaths: [String] = []

        // Match macotron.xxx.yyy patterns
        let apiPattern = try! NSRegularExpression(pattern: #"macotron\.(\w+)\.(\w+)"#)
        let matches = apiPattern.matches(in: js, range: NSRange(js.startIndex..., in: js))
        for match in matches {
            if let r1 = Range(match.range(at: 1), in: js),
               let r2 = Range(match.range(at: 2), in: js) {
                apis.insert("\(js[r1]).\(js[r2])")
            }
        }

        // Extract string arguments from shell.run("...") calls
        let shellPattern = try! NSRegularExpression(pattern: #"shell\.run\(\s*["'`]([^"'`]+)["'`]"#)
        let shellMatches = shellPattern.matches(in: js, range: NSRange(js.startIndex..., in: js))
        for match in shellMatches {
            if let r = Range(match.range(at: 1), in: js) {
                shellCmds.append(String(js[r]))
            }
        }

        // Extract URLs from http calls
        let httpPattern = try! NSRegularExpression(pattern: #"http\.(post|put|delete|get)\(\s*["'`]([^"'`]+)["'`]"#)
        let httpMatches = httpPattern.matches(in: js, range: NSRange(js.startIndex..., in: js))
        for match in httpMatches {
            if let r = Range(match.range(at: 2), in: js) {
                networkURLs.append(String(js[r]))
            }
        }

        // Extract paths from fs calls
        let fsPattern = try! NSRegularExpression(pattern: #"fs\.(write|delete|remove)\(\s*["'`]([^"'`]+)["'`]"#)
        let fsMatches = fsPattern.matches(in: js, range: NSRange(js.startIndex..., in: js))
        for match in fsMatches {
            if let r = Range(match.range(at: 2), in: js) {
                filePaths.append(String(js[r]))
            }
        }

        let maxTier = apis.compactMap { apiTiers[$0] }.max() ?? .safe

        return SnippetManifest(
            apisUsed: apis,
            shellCommands: shellCmds,
            networkTargets: networkURLs,
            fileTargets: filePaths,
            tier: maxTier
        )
    }

    /// Check if a snippet can be auto-fixed (no dangerous APIs, no opt-out pragma)
    public static func canAutoFix(source: String) -> Bool {
        if source.contains("// macotron:no-autofix") { return false }
        for pattern in dangerousPatterns {
            if source.contains(pattern) { return false }
        }
        return true
    }
}
