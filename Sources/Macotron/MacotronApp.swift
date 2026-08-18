// MacotronApp.swift — @main entry point
import AppKit
import SwiftUI

@main
struct MacotronApp {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            let code = MainActor.assumeIsolated {
                PluginChecker.run(arguments: CommandLine.arguments)
            }
            exit(code)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
