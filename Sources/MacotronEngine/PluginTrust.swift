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

public final class KeychainHashStore: PluginHashStore {
    public init() {}

    public static func account(_ filename: String) -> String {
        "macotron.plugin.hash.\(filename)"
    }

    public func read(filename: String) -> String? {
        KeychainStore.read(account: Self.account(filename))
    }

    public func write(filename: String, hash: String) {
        KeychainStore.write(account: Self.account(filename), value: hash)
    }

    public func delete(filename: String) {
        KeychainStore.delete(account: Self.account(filename))
    }

    public func hasAnyHashes() -> Bool {
        false
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

    public static func matches(filename: String, source: String) -> Bool {
        guard let approved = store.read(filename: filename) else { return false }
        return approved == PluginHash.sha256(source: source)
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
            /(?m)^\s*import\s+(?:[^"'\n]+\bfrom\s+)?["']([^"']+)["']/,
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
    public static func grandfatherIfEmpty(pluginsDir: URL, store: PluginHashStore = store) {
        if store is KeychainHashStore {
            if currentFilesHaveAnyHash(pluginsDir: pluginsDir, store: store) { return }
        } else if store.hasAnyHashes() {
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "js" {
            guard let hash = PluginHash.sha256(file: file) else { continue }
            store.write(filename: file.lastPathComponent, hash: hash)
        }
    }

    private static func currentFilesHaveAnyHash(pluginsDir: URL, store: PluginHashStore) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pluginsDir, includingPropertiesForKeys: nil
        )) ?? []
        return files.contains { file in
            file.pathExtension == "js" && store.read(filename: file.lastPathComponent) != nil
        }
    }
}
