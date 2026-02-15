// LocalStorageModule.swift — Web-compatible localStorage backed by a JSON file
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "localStorage")

@MainActor
public final class LocalStorageModule: NativeModule {
    public let name = "localStorage"

    public var defaultOptions: [String: Any] {
        [:] // "configDir" must be supplied externally
    }

    /// In-memory mirror of the JSON store
    private var store: [String: String] = [:]

    /// Path to the backing JSON file
    private var filePath: URL?

    public init() {}

    // MARK: - NativeModule

    public func register(in engine: Engine, options: [String: Any]) {
        // Resolve configDir from options
        if let configDir = options["configDir"] as? String {
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
        JS_SetPropertyStr(ctx, storageObj, "getItem", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Null() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Null() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Null() }

            if let mod = engine.configStore["__localStorageModule"] as? LocalStorageModule,
               let value = mod.store[key] {
                return JSBridge.newString(ctx, value)
            }
            return QJS_Null()
        }, "getItem", 1))

        // --- setItem(key, value) ---
        JS_SetPropertyStr(ctx, storageObj, "setItem", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            let value = JSBridge.toString(ctx, argv[1]) ?? ""

            if let mod = engine.configStore["__localStorageModule"] as? LocalStorageModule {
                mod.store[key] = value
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }, "setItem", 2))

        // --- removeItem(key) ---
        JS_SetPropertyStr(ctx, storageObj, "removeItem", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            guard let key = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            if let mod = engine.configStore["__localStorageModule"] as? LocalStorageModule {
                mod.store.removeValue(forKey: key)
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }, "removeItem", 1))

        // --- clear() ---
        JS_SetPropertyStr(ctx, storageObj, "clear", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return QJS_Undefined() }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            if let mod = engine.configStore["__localStorageModule"] as? LocalStorageModule {
                mod.store.removeAll()
                mod.saveToDisk()
            }
            return QJS_Undefined()
        }, "clear", 0))

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
            logger.info("localStorage: no existing data at \(filePath.path), starting fresh")
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
