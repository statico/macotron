// AppMenu.swift — AX menu-item selection
import ApplicationServices
import AppKit
import Foundation

enum AppMenu {
    static func stripShortcut(_ title: String) -> String {
        if let tab = title.firstIndex(of: "\t") {
            return String(title[..<tab])
        }
        return title
    }

    static func match(_ actual: String, _ wanted: String) -> Bool {
        let a = stripShortcut(actual)
        if a == wanted { return true }
        if a.hasPrefix(wanted) {
            let rest = a.dropFirst(wanted.count)
            return rest.allSatisfy { $0 == "…" || $0 == "." }
        }
        return false
    }

    static func select(pid: pid_t, path: [String]) -> Bool {
        guard !path.isEmpty else { return false }
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }
        return walk(menuBar as! AXUIElement, path: path[...])
    }

    private static func walk(_ element: AXUIElement, path: ArraySlice<String>) -> Bool {
        guard let wanted = path.first else { return false }
        for child in children(element) {
            guard match(title(child), wanted) else { continue }
            if path.count == 1 {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
            if let menu = submenu(child) {
                return walk(menu, path: path.dropFirst())
            }
            return walk(child, path: path.dropFirst())
        }
        return false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let kids = ref as? [AXUIElement] else {
            return []
        }
        return kids
    }

    private static func title(_ element: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String else {
            return ""
        }
        return title
    }

    private static func submenu(_ item: AXUIElement) -> AXUIElement? {
        children(item).first
    }
}

enum AppControl {
    static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.statico.macotron"

    static func running(_ bundleID: String?) -> NSRunningApplication? {
        if let bundleID, !bundleID.isEmpty {
            return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
        }
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != ownBundleID {
            return app
        }
        return nil
    }

    static func hide(_ bundleID: String?) -> Bool {
        running(bundleID)?.hide() ?? false
    }

    static func quit(_ bundleID: String?) -> Bool {
        running(bundleID)?.terminate() ?? false
    }

    static func info(_ app: NSRunningApplication) -> [String: Any]? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return [
            "name": app.localizedName ?? bundleID,
            "bundleID": bundleID,
            "pid": Int(app.processIdentifier),
        ]
    }
}
