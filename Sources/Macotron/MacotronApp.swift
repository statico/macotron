// MacotronApp.swift — @main entry point
import AppKit
import SwiftUI

@main
struct MacotronApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
