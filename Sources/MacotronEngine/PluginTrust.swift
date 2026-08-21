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
