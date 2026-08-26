// PluginBlocklist.swift — Bytes Macotron refuses to run, whatever their source.
//
// Delisting a repository stops discovery. It never stops code that is already
// installed on a machine. This list is the only thing that does, so it is
// checked before the trust ledger and before hot reload.
//
// The file lives beside appcast.xml on the update host and is usually empty:
//   { "blocked": [ { "sha256": "…", "reason": "Sends the clipboard away." } ] }
import Foundation
import os

@MainActor
public enum PluginBlocklist {
    public static var url = URL(string: "https://macotron.statico.io/blocked.json")!

    private static let logger = Logger(subsystem: "io.statico.macotron", category: "blocklist")
    private static var reasons: [String: String] = [:]
    private static var loadedCache = false

    /// nil means the bytes are not blocked.
    public static func reason(hash: String) -> String? {
        loadCacheIfNeeded()
        return reasons[hash.lowercased()]
    }

    public static var isEmpty: Bool {
        loadCacheIfNeeded()
        return reasons.isEmpty
    }

    /// Answers true when the set changed, so the caller can reload plugins.
    @discardableResult
    public static func refresh(session: URLSession = .shared) async -> Bool {
        loadCacheIfNeeded()
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("Macotron", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = parse(data) else {
            logger.info("blocklist refresh failed, keeping \(reasons.count) cached entries")
            return false
        }
        // A cached list is never dropped for a smaller live one without proof
        // the fetch worked, and it just did.
        guard parsed != reasons else { return false }
        reasons = parsed
        writeCache(data)
        logger.info("blocklist now holds \(parsed.count) hashes")
        return true
    }

    static func parse(_ data: Data) -> [String: String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["blocked"] as? [[String: Any]] else {
            return nil
        }
        var out: [String: String] = [:]
        for row in rows {
            guard let hash = (row["sha256"] as? String)?.lowercased(), !hash.isEmpty else { continue }
            out[hash] = (row["reason"] as? String) ?? "Blocked by Macotron."
        }
        return out
    }

    // MARK: - Cache

    /// Cached on disk so a Mac that starts up offline still refuses.
    static var cacheURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let appDir = dir.appending(path: "Macotron")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appending(path: "blocked.json")
    }

    private static func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL), let parsed = parse(data) else {
            return
        }
        reasons = parsed
    }

    private static func writeCache(_ data: Data) {
        guard let cacheURL else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Tests only.
    public static func reset(to entries: [String: String]) {
        reasons = entries
        loadedCache = true
    }
}
