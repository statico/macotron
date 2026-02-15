// FileSystemModule.swift — macotron.fs: file system operations from JS
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "fs")

// MARK: - FSWatcher Support

/// Thread-safe global registry for active FSEvent watchers.
/// FSEventStreamCreate requires a C function pointer (no captures), so the
/// callback uses this registry to look up the owning module and dispatch
/// events back to the main thread.
private final class FSWatcherRegistry: @unchecked Sendable {
    static let shared = FSWatcherRegistry()

    private let lock = NSLock()
    private var watchers: [UInt64: Entry] = [:]
    private var nextID: UInt64 = 1

    struct Entry {
        let watchedPath: String
        weak var module: FileSystemModule?
    }

    func allocate(path: String, module: FileSystemModule) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        watchers[id] = Entry(watchedPath: path, module: module)
        return id
    }

    func lookup(_ id: UInt64) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return watchers[id]
    }

    func remove(_ id: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        watchers.removeValue(forKey: id)
    }
}

/// Tracks a single active fs.watch watcher on the MainActor side.
@MainActor
private final class ActiveWatcher {
    let id: UInt64
    let path: String
    let callback: JSValue   // JS_DupValue'd — must be freed on cleanup
    let ctx: OpaquePointer  // QuickJS context
    var stream: FSEventStreamRef?

    init(id: UInt64, path: String, callback: JSValue, ctx: OpaquePointer) {
        self.id = id
        self.path = path
        self.callback = callback
        self.ctx = ctx
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        JS_FreeValue(ctx, callback)
        FSWatcherRegistry.shared.remove(id)
    }
}

// MARK: - FileSystemModule

@MainActor
public final class FileSystemModule: NativeModule {
    public let name = "fs"
    public let moduleVersion = 1

    public var defaultOptions: [String: Any] {
        ["sandboxRoot": NSHomeDirectory()]
    }

    /// Active fs.watch watchers, keyed by watcher ID.
    private var activeWatchers: [UInt64: ActiveWatcher] = [:]

    /// Weak reference to the engine for invoking JS callbacks from FSEvent dispatch.
    private weak var engine: Engine?

    public init() {}

    // MARK: - Watcher Lifecycle

    /// Called on the main thread when an FSEvent fires for a watcher we own.
    fileprivate func handleFSEvent(watcherID: UInt64, paths: [String], flags: [UInt32]) {
        guard let watcher = activeWatchers[watcherID],
              let engine else { return }
        let ctx = engine.context!

        for (i, changedPath) in paths.enumerated() {
            let eventFlags = flags[i]
            let eventType: String
            if eventFlags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                eventType = "deleted"
            } else if eventFlags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
                        || eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                eventType = "created"
            } else {
                eventType = "modified"
            }

            let eventObj = JSBridge.newObject(ctx, [
                "path": changedPath,
                "type": eventType,
            ])

            var args = [eventObj]
            let result = JS_Call(ctx, watcher.callback, QJS_Undefined(), 1, &args)
            if JS_IsException(result) {
                let errStr = JSBridge.getExceptionString(ctx)
                logger.error("fs.watch callback error: \(errStr)")
            }
            JS_FreeValue(ctx, result)
            JS_FreeValue(ctx, eventObj)
        }

        engine.drainJobQueue()
    }

    /// Stop a specific watcher by ID.
    fileprivate func stopWatcher(_ id: UInt64) {
        guard let watcher = activeWatchers.removeValue(forKey: id) else { return }
        watcher.stop()
        logger.info("fs.watch stopped: \(watcher.path)")
    }

    /// Stop all active watchers.
    private func stopAllWatchers() {
        for (_, watcher) in activeWatchers {
            watcher.stop()
        }
        activeWatchers.removeAll()
    }

    // MARK: - Register

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let fsObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.fs.read(path) -> string
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "read", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.read requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.read: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
                logger.info("fs.read: \(expandedPath)")
                return JSBridge.newString(ctx, content)
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.read failed: \(error.localizedDescription)")
            }
        }, "read", 1))

        // -----------------------------------------------------------------
        // macotron.fs.write(path, content) -> void
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "write", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "fs.write requires path and content arguments")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.write: path must be a string")
            }
            guard let content = JSBridge.toString(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "fs.write: content must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let dir = (expandedPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true
                )
                try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                logger.info("fs.write: \(expandedPath) (\(content.count) chars)")
                return QJS_Undefined()
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.write failed: \(error.localizedDescription)")
            }
        }, "write", 2))

        // -----------------------------------------------------------------
        // macotron.fs.exists(path) -> bool
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "exists", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.exists requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.exists: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            let exists = FileManager.default.fileExists(atPath: expandedPath)
            return JSBridge.newBool(ctx, exists)
        }, "exists", 1))

        // -----------------------------------------------------------------
        // macotron.fs.list(path) -> string[]
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "list", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "fs.list requires a path argument")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.list: path must be a string")
            }

            let expandedPath = NSString(string: path).expandingTildeInPath
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
                let jsArr = JS_NewArray(ctx)
                for (i, entry) in entries.enumerated() {
                    JS_SetPropertyUint32(ctx, jsArr, UInt32(i),
                                         JSBridge.newString(ctx, entry))
                }
                logger.info("fs.list: \(expandedPath) (\(entries.count) entries)")
                return jsArr
            } catch {
                return QJS_ThrowInternalError(ctx, "fs.list failed: \(error.localizedDescription)")
            }
        }, "list", 1))

        // -----------------------------------------------------------------
        // $$__fsStopWatcher(id) — hidden native helper called by stop closures
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, global, "$$__fsStopWatcher",
            JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
                guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
                var watcherIDRaw: Double = 0
                JS_ToFloat64(ctx, &watcherIDRaw, argv[0])
                let watcherID = UInt64(watcherIDRaw)

                guard let entry = FSWatcherRegistry.shared.lookup(watcherID),
                      let module = entry.module else {
                    return QJS_Undefined()
                }
                module.stopWatcher(watcherID)
                return QJS_Undefined()
            }, "$$__fsStopWatcher", 1))

        // -----------------------------------------------------------------
        // macotron.fs.watch(path, callback) -> () => void
        //
        // Watches a file or directory for changes using macOS FSEvents.
        // Calls callback({path: string, type: "modified"|"created"|"deleted"})
        // whenever a change is detected. Returns a stop function that cancels
        // the watcher when called.
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, fsObj, "watch", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "fs.watch requires path and callback arguments")
            }
            guard let path = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "fs.watch: path must be a string")
            }

            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else {
                return QJS_ThrowInternalError(ctx, "fs.watch: engine not available")
            }
            let _ = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            let expandedPath = NSString(string: path).expandingTildeInPath

            guard FileManager.default.fileExists(atPath: expandedPath) else {
                return QJS_ThrowInternalError(ctx, "fs.watch: path does not exist: \(expandedPath)")
            }

            // FSEvents watches directories. If the target is a file, watch its parent.
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir)
            let watchDir = isDir.boolValue ? expandedPath : (expandedPath as NSString).deletingLastPathComponent

            // Protect the JS callback from garbage collection
            let protectedCallback = JS_DupValue(ctx, argv[1])

            // Retrieve the FileSystemModule via its pointer stored as a hidden global.
            // (C function callbacks cannot capture Swift references, so we pass the
            // module pointer through the JS context as a float64-encoded address.)
            let globalObj = JS_GetGlobalObject(ctx)
            let modulePtrVal = JS_GetPropertyStr(ctx, globalObj, "$$__fsModule")
            JS_FreeValue(ctx, globalObj)

            var ptrBits: Double = 0
            JS_ToFloat64(ctx, &ptrBits, modulePtrVal)
            JS_FreeValue(ctx, modulePtrVal)

            guard let moduleRawPtr = UnsafeMutableRawPointer(bitPattern: UInt(ptrBits)) else {
                JS_FreeValue(ctx, protectedCallback)
                return QJS_ThrowInternalError(ctx, "fs.watch: module reference lost")
            }
            let module = Unmanaged<FileSystemModule>.fromOpaque(moduleRawPtr).takeUnretainedValue()

            // Register in the global watcher registry (bridges C callback → module)
            let watcherID = FSWatcherRegistry.shared.allocate(path: expandedPath, module: module)

            let watcher = ActiveWatcher(
                id: watcherID,
                path: expandedPath,
                callback: protectedCallback,
                ctx: ctx
            )

            // Create FSEventStream. The watcher ID is passed through the context's
            // info pointer so the C callback can identify which watcher fired.
            var streamContext = FSEventStreamContext()
            streamContext.info = UnsafeMutableRawPointer(bitPattern: UInt(watcherID))

            let pathCF = watchDir as CFString
            let pathsToWatch = [pathCF] as CFArray

            let stream = FSEventStreamCreate(
                nil,
                { _, info, numEvents, eventPaths, eventFlags, _ in
                    guard let info else { return }
                    let id = UInt64(UInt(bitPattern: info))

                    guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                        return
                    }

                    var flags: [UInt32] = []
                    for i in 0..<numEvents {
                        flags.append(eventFlags[i])
                    }

                    DispatchQueue.main.async {
                        guard let entry = FSWatcherRegistry.shared.lookup(id),
                              let module = entry.module else { return }
                        module.handleFSEvent(watcherID: id, paths: cfPaths, flags: flags)
                    }
                },
                &streamContext,
                pathsToWatch,
                UInt64(kFSEventStreamEventIdSinceNow),
                0.3, // latency in seconds
                UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            )

            guard let stream else {
                watcher.stop()
                return QJS_ThrowInternalError(ctx, "fs.watch: failed to create FSEventStream")
            }

            watcher.stream = stream
            module.activeWatchers[watcherID] = watcher

            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)

            logger.info("fs.watch: watching \(expandedPath) (id=\(watcherID))")

            // Return a JS stop function. We create a small JS closure that captures
            // the watcher ID and calls the native $$__fsStopWatcher(id) helper.
            let closureJS = "(function(){ var _id = \(watcherID); return function(){ $$__fsStopWatcher(_id); }; })()"
            let stopFn = closureJS.withCString { cStr in
                JS_Eval(ctx, cStr, closureJS.utf8.count, "<fs.watch>", Int32(JS_EVAL_TYPE_GLOBAL))
            }

            return stopFn
        }, "watch", 2))

        // Store self pointer as a hidden global so the watch C callback can
        // retrieve the FileSystemModule instance. Encoded as float64 (macOS
        // uses 48-bit virtual addresses, well within float64 precision).
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let ptrAsDouble = Double(UInt(bitPattern: selfPtr))
        JS_SetPropertyStr(ctx, global, "$$__fsModule", JSBridge.newFloat64(ctx, ptrAsDouble))

        JS_SetPropertyStr(ctx, macotron, "fs", fsObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        stopAllWatchers()
        engine = nil
    }
}
