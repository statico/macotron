// LocalStorageModule.swift — Web-compatible localStorage backed by a JSON file
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "localStorage")

@MainActor
public final class LocalStorageModule: NativeModule {
    public let name = "localStorage"

    /// Where the JSON store lives. Nil keeps storage in memory, which is what
    /// the dry-run checker wants and what every plugin using localStorage got
    /// by accident until the host started passing this in.
    private let configDir: String?

    /// In-memory mirror of the JSON store
    private var store: [String: String] = [:]

    /// Path to the backing JSON file
    private var filePath: URL?

    public init(configDir: String? = nil) {
        self.configDir = configDir
    }

    // MARK: - NativeModule

    public func register(in engine: Engine, options: [String: Any]) {
        // Resolve configDir from options, else the one the host passed in.
        if let configDir = options["configDir"] as? String ?? self.configDir {
            let dataDir = URL(fileURLWithPath: configDir).appendingPathComponent("data")
            let fm = FileManager.default
            if !fm.fileExists(atPath: dataDir.path) {
                try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            }
            filePath = dataDir.appendingPathComponent("localStorage.json")
            loadFromDisk()
        } else {
            logger.warning("LocalStorageModule: no configDir provided, storage will be ephemeral")
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)

        // localStorage is a global object (NOT under macotron namespace)
        let storageObj = JS_NewObject(ctx)

        // --- getItem(key) → string | null ---
        JSBridge.fn(ctx, storageObj, "getItem", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Null() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Null() }

            if let mod: LocalStorageModule = Engine.module(ctx, "__localStorageModule"),
               let value = mod.store[key] {
                return JSBridge.newString(ctx, value)
            }
            return QJS_Null()
        }

        // --- setItem(key, value) ---
        JSBridge.fn(ctx, storageObj, "setItem", 2) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let value = JSBridge.toString(ctx, argv[1]) ?? ""

            if let mod: LocalStorageModule = Engine.module(ctx, "__localStorageModule") {
                mod.store[key] = value
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }

        // --- removeItem(key) ---
        JSBridge.fn(ctx, storageObj, "removeItem", 1) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod: LocalStorageModule = Engine.module(ctx, "__localStorageModule") {
                mod.store.removeValue(forKey: key)
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }

        // --- clear() ---
        JSBridge.fn(ctx, storageObj, "clear", 0) { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            if let mod: LocalStorageModule = Engine.module(ctx, "__localStorageModule") {
                mod.store.removeAll()
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }

        JS_SetPropertyStr(ctx, global, "localStorage", storageObj)
        JS_FreeValue(ctx, global)

        // Stash self so C callbacks can retrieve it
        engine.configStore["__localStorageModule"] = self
    }

    public func cleanup() {
        saveToDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let filePath else { return }
        do {
            let data = try Data(contentsOf: filePath)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                store = dict
            }
        } catch {
            // File doesn't exist yet or is malformed — start with empty store
        }
    }

    private func saveToDisk() {
        guard let filePath else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: store, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: filePath, options: .atomic)
        } catch {
            logger.error("localStorage: failed to save: \(error.localizedDescription)")
        }
    }
}
