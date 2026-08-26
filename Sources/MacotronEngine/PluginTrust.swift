import Foundation

public protocol PluginHashStore: AnyObject {
    func read(filename: String) -> String?
    func write(filename: String, hash: String)
    func delete(filename: String)
    func hasAnyHashes() -> Bool
}

public final class MemoryHashStore: PluginHashStore {
    public var hashes: [String: String] = [:]

    public init() {}

    public func read(filename: String) -> String? { hashes[filename] }
    public func write(filename: String, hash: String) { hashes[filename] = hash }
    public func delete(filename: String) { hashes.removeValue(forKey: filename) }
    public func hasAnyHashes() -> Bool { !hashes.isEmpty }
}

/// Ledger lives in the host-only trust service, isolated from plugin secrets
/// so `macotron.keychain.*` can never forge or wipe approvals.
public final class KeychainHashStore: PluginHashStore {
    public init() {}

    public static func account(_ filename: String) -> String {
        "macotron.plugin.hash.\(filename)"
    }

    public func read(filename: String) -> String? {
        KeychainStore.read(account: Self.account(filename), service: KeychainStore.trustServiceName)
    }

    public func write(filename: String, hash: String) {
        KeychainStore.write(
            account: Self.account(filename), value: hash,
            service: KeychainStore.trustServiceName)
    }

    public func delete(filename: String) {
        KeychainStore.delete(account: Self.account(filename), service: KeychainStore.trustServiceName)
    }

    public func hasAnyHashes() -> Bool {
        KeychainStore.accounts(service: KeychainStore.trustServiceName)
            .contains { $0.hasPrefix("macotron.plugin.hash.") }
    }
}

@MainActor
public enum PluginTrust {
    public static var store: PluginHashStore = KeychainHashStore()

    public static func approve(filename: String, hash: String) {
        store.write(filename: filename, hash: hash)
    }

    public static func approve(filename: String, source: String) {
        approve(filename: filename, hash: PluginHash.sha256(source: source))
    }

    /// True once this filename has ever been approved. A pending plugin that
    /// is not known is new on disk rather than an edit of something that ran.
    public static func isKnown(filename: String) -> Bool {
        store.read(filename: filename) != nil
    }

    /// The block list wins over the ledger: bytes that were approved before
    /// they were known to be bad still stop running.
    public static func matches(filename: String, source: String) -> Bool {
        let hash = PluginHash.sha256(source: source)
        guard PluginBlocklist.reason(hash: hash) == nil else { return false }
        guard let approved = store.read(filename: filename) else { return false }
        return approved == hash
    }

    /// Approve every workdir file reachable through statically visible import
    /// specifiers (`import … from "x"` and `import("x")` literals) in `source`,
    /// keyed by workdir-relative path. Files outside `baseDir` are skipped —
    /// the loader never gates them.
    public static func approveImports(
        in source: String,
        importerDir: URL,
        baseDir: URL,
        store: PluginHashStore = store
    ) {
        var visited: Set<String> = []
        var queue: [(source: String, dir: URL)] = [(source, importerDir)]
        while let (src, dir) = queue.popLast() {
            for spec in importSpecifiers(in: src) {
                var path: String
                if spec.hasPrefix("/") {
                    path = spec
                } else if spec.hasPrefix(".") {
                    path = dir.appending(path: spec).path(percentEncoded: false)
                } else {
                    path = baseDir.appending(path: spec).path(percentEncoded: false)
                }
                if !path.hasSuffix(".js") { path += ".js" }
                let file = URL(fileURLWithPath: path).standardizedFileURL
                guard let key = workdirKey(path: path, baseDir: baseDir),
                      visited.insert(key).inserted,
                      let imported = try? String(contentsOf: file, encoding: .utf8)
                else { continue }
                store.write(filename: key, hash: PluginHash.sha256(source: imported))
                queue.append((imported, file.deletingLastPathComponent()))
            }
        }
    }

    nonisolated private static func importSpecifiers(in source: String) -> [String] {
        let patterns = [
            /import\s*\(\s*["']([^"']+)["']\s*\)/,
            /(?m)^\s*import\s+(?:[^"']+?\bfrom\s+)?["']([^"']+)["']/,
        ]
        return patterns.flatMap { pattern in
            source.matches(of: pattern).map { String($0.output.1) }
        }
    }

    /// Ledger key for a file under `baseDir` (workdir-relative path), nil if outside.
    nonisolated static func workdirKey(path: String, baseDir: URL) -> String? {
        var base = baseDir.standardizedFileURL.path(percentEncoded: false)
        if !base.hasSuffix("/") { base += "/" }
        let full = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
        guard full.hasPrefix(base) else { return nil }
        return String(full.dropFirst(base.count))
    }

    public static func migrateHash(
        from oldFilename: String,
        to newFilename: String,
        store: PluginHashStore = store
    ) {
        guard let hash = store.read(filename: oldFilename) else { return }
        store.write(filename: newFilename, hash: hash)
        store.delete(filename: oldFilename)
    }

    /// First upgrade: if the ledger is empty, treat every current plugin as approved.
    /// Only the host can write the trust service, so an empty ledger genuinely
    /// means never-approved — plugins cannot wipe it to force a re-trust.
    public static func grandfatherIfEmpty(pluginsDir: URL, store: PluginHashStore = store) {
        if store.hasAnyHashes() { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "js" {
            guard let hash = PluginHash.sha256(file: file) else { continue }
            store.write(filename: file.lastPathComponent, hash: hash)
        }
    }
}
