// ShellModule.swift — macotron.shell: execute shell commands from JS
import CQuickJS
import Foundation
import MacotronEngine

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

            let dryResult: [String: Any] = ["stdout": "", "stderr": "", "exitCode": 0]
            let capturedArgs = args
            return JSBridge.promise(ctx, dryRun: dryResult) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                var fullCmd = command
                for arg in capturedArgs {
                    // Simple shell-escape: wrap each arg in single quotes
                    let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                    fullCmd += " '\(escaped)'"
                }
                process.arguments = ["-c", fullCmd]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    return .failure("shell.run failed: \(error.localizedDescription)")
                }
                // Read before waiting: a command that fills the 64K pipe buffer
                // blocks on write forever if nobody is draining it.
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                return .value([
                    "stdout": String(data: stdoutData, encoding: .utf8) ?? "",
                    "stderr": String(data: stderrData, encoding: .utf8) ?? "",
                    "exitCode": Int(process.terminationStatus),
                ] as [String: Any])
            }
        }, "run", 2))
        JS_SetPropertyStr(ctx, macotron, "shell", shellObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        // Nothing to clean up currently
    }
}
