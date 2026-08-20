// PluginChecker.swift — Macotron --check dry-run plugin load
import Foundation
import MacotronEngine
import Modules

@MainActor
enum PluginChecker {
    static func run(arguments: [String]) -> Int32 {
        guard let checkIndex = arguments.firstIndex(of: "--check") else {
            fputs("Internal error: --check missing from arguments\n", stderr)
            return 1
        }

        let pathArgs = Array(arguments[(checkIndex + 1)...]).filter { !$0.hasPrefix("-") }

        let files: [URL]
        do {
            files = try resolveFiles(pathArgs)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return 1
        }

        guard !files.isEmpty else {
            fputs("No plugin files to check.\n", stderr)
            return 1
        }

        guard let runtimeJS = loadRuntimeJS() else {
            fputs("Could not load macotron-runtime.js from bundle.\n", stderr)
            return 1
        }

        let engine = Engine()
        engine.dryRun = true
        registerModules(in: engine)
        engine.registerAllModules()
        engine.evaluate(runtimeJS, filename: "macotron-runtime.js")

        let host = SemVer(Engine.apiVersion) ?? SemVer(major: 1, minor: 0, patch: 0)
        var allOK = true

        for file in files {
            let display = file.path(percentEncoded: false)
            let result = checkFile(file, display: display, engine: engine, host: host)
            if let error = result {
                print("FAIL \(display): \(error)")
                allOK = false
            } else {
                print("OK \(display)")
            }
        }

        return allOK ? 0 : 1
    }

    private static func resolveFiles(_ pathArgs: [String]) throws -> [URL] {
        if !pathArgs.isEmpty {
            return pathArgs.map { path in
                if path.hasPrefix("/") {
                    URL(fileURLWithPath: path)
                } else {
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appending(path: path)
                }
            }
        }

        guard let workdir = PluginWorkspace.resolveFromDefaults() else {
            throw CheckerError(
                "No plugins directory configured. Pass paths (e.g. plugins/foo.js) or set up a Macotron workdir."
            )
        }
        let pluginsDir = PluginWorkspace(root: workdir).pluginsDir
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: nil
        ) else {
            throw CheckerError("Could not read plugins directory: \(pluginsDir.path(percentEncoded: false))")
        }
        return entries.filter { $0.pathExtension == "js" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    private static func checkFile(
        _ file: URL,
        display: String,
        engine: Engine,
        host: SemVer
    ) -> String? {
        let source: String
        do {
            source = try String(contentsOf: file, encoding: .utf8)
        } catch {
            return "could not read file: \(error.localizedDescription)"
        }

        switch PluginNeeds.parse(source) {
        case .failure(let error):
            return error.message
        case .success(let needs):
            if needs > host {
                return PluginNeeds.unmetMessage(needs: needs, host: host)
            }
        }

        engine.currentEvaluatingFile = file.lastPathComponent
        defer { engine.currentEvaluatingFile = nil }

        let (_, error) = engine.evaluate(Engine.isolatedPlugin(source), filename: display)
        return error
    }

    private static func loadRuntimeJS() -> String? {
        let url = Bundle.module.url(forResource: "macotron-runtime", withExtension: "js")
            ?? Bundle.main.url(forResource: "macotron-runtime", withExtension: "js")
        guard let url, let js = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return js
    }

    private static func registerModules(in engine: Engine) {
        engine.addModule(ShellModule())
        engine.addModule(FileSystemModule())
        engine.addModule(NotifyModule())
        engine.addModule(DialogModule())
        engine.addModule(ClipboardModule())
        engine.addModule(KeyboardModule())
        engine.addModule(EventModule())
        engine.addModule(WindowModule())
        engine.addModule(AppModule())
        engine.addModule(ScreenModule())
        engine.addModule(SystemModule())
        engine.addModule(DisplayModule())
        engine.addModule(HTTPModule())
        engine.addModule(LocalStorageModule())
        engine.addModule(KeychainModule())
        engine.addModule(MenuBarModule())
        engine.addModule(URLSchemeModule())
        engine.addModule(SpotlightModule())
        engine.addModule(AIModule())
        engine.addModule(PanelModule())
        engine.addModule(LauncherModule())
        engine.addModule(NotesModule())
        engine.addModule(ContactsModule())
        engine.addModule(MediaModule())
        engine.addModule(PowerModule())
        engine.addModule(NetworkModule())
        engine.addModule(AudioModule())
        engine.addModule(SpacesModule())
        engine.addModule(USBModule())
        engine.addModule(HIDModule())
        engine.addModule(QRModule())
        engine.addModule(ShortcutsModule())
    }
}

private struct CheckerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
