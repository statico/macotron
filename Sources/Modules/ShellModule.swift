// ShellModule.swift — macotron.shell: execute shell commands from JS
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "com.macotron", category: "shell")

@MainActor
public final class ShellModule: NativeModule {
    public let name = "shell"
    public let moduleVersion = 1

    /// Commands that are always allowed without prompting.
    /// Extend this list or make it configurable via options.
    private var allowlist: Set<String> = [
        "echo", "date", "whoami", "uname", "sw_vers", "which", "printenv",
        "ls", "cat", "head", "tail", "wc", "sort", "uniq", "grep", "find",
        "ps", "uptime", "df", "du", "hostname", "id",
    ]

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        // Merge any user-supplied allowlist additions
        if let extra = options["allowlist"] as? [String] {
            allowlist.formUnion(extra)
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let shellObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.shell.run(command, args?) -> Promise<{stdout, stderr, exitCode}>
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, shellObj, "run", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }

            // Extract command string
            guard let command = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "shell.run: first argument must be a string")
            }

            // Extract optional args array
            var args: [String] = []
            if argc > 1 && !JS_IsUndefined(argv[1]) && !JS_IsNull(argv[1]) {
                // Read array elements
                let lengthVal = JSBridge.getProperty(ctx, argv[1], "length")
                let length = JSBridge.toInt32(ctx, lengthVal)
                JS_FreeValue(ctx, lengthVal)
                for i in 0..<length {
                    let elem = JS_GetPropertyUint32(ctx, argv[1], UInt32(i))
                    if let s = JSBridge.toString(ctx, elem) {
                        args.append(s)
                    }
                    JS_FreeValue(ctx, elem)
                }
            }

            // Create promise
            var resolvingFuncs = [JSValue](repeating: QJS_Undefined(), count: 2)
            let promise = JS_NewPromiseCapability(ctx, &resolvingFuncs)
            let resolve = JS_DupValue(ctx, resolvingFuncs[0])
            let reject = JS_DupValue(ctx, resolvingFuncs[1])
            JS_FreeValue(ctx, resolvingFuncs[0])
            JS_FreeValue(ctx, resolvingFuncs[1])

            // Retrieve engine reference
            let opaque = JS_GetContextOpaque(ctx)
            guard let opaque else { return promise }
            let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()

            // Run process on a background queue, resolve/reject on main
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    // Build full command line: command + args
                    var fullCmd = command
                    for arg in args {
                        // Simple shell-escape: wrap each arg in single quotes
                        let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                        fullCmd += " '\(escaped)'"
                    }
                    process.arguments = ["-c", fullCmd]

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    try process.run()
                    process.waitUntilExit()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                    let exitCode = process.terminationStatus

                    DispatchQueue.main.async {
                        let resultObj = JS_NewObject(ctx)
                        JSBridge.setProperty(ctx, resultObj, "stdout",
                                             JSBridge.newString(ctx, stdoutStr))
                        JSBridge.setProperty(ctx, resultObj, "stderr",
                                             JSBridge.newString(ctx, stderrStr))
                        JSBridge.setProperty(ctx, resultObj, "exitCode",
                                             JSBridge.newInt32(ctx, exitCode))

                        var resultArg = resultObj
                        _ = JS_Call(ctx, resolve, QJS_Undefined(), 1, &resultArg)
                        JS_FreeValue(ctx, resolve)
                        JS_FreeValue(ctx, reject)
                        JS_FreeValue(ctx, resultObj)
                        engine.drainJobQueue()
                    }
                } catch {
                    DispatchQueue.main.async {
                        var errArg = JSBridge.newString(ctx, "shell.run failed: \(error.localizedDescription)")
                        _ = JS_Call(ctx, reject, QJS_Undefined(), 1, &errArg)
                        JS_FreeValue(ctx, resolve)
                        JS_FreeValue(ctx, reject)
                        JS_FreeValue(ctx, errArg)
                        engine.drainJobQueue()
                    }
                }
            }

            logger.info("shell.run: \(command) \(args)")
            return promise
        }, "run", 2))
        JS_SetPropertyStr(ctx, macotron, "shell", shellObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        // Nothing to clean up currently
    }
}
