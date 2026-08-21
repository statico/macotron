import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

final class AXHandleTable<Value> {
    private var next: Int32 = 1
    private var items: [Int32: Value] = [:]

    func alloc(_ value: Value) -> Int32 {
        let id = next
        next += 1
        items[id] = value
        return id
    }

    func lookup(_ id: Int32) -> Value? {
        items[id]
    }

    func clear() {
        items.removeAll()
        next = 1
    }
}

enum AXAttrs {
    static func normalizeRole(_ role: String) -> String {
        let lower = role.lowercased()
        return lower.hasPrefix("ax") ? String(lower.dropFirst(2)) : lower
    }

    static func matchRole(_ actual: String, _ wanted: String) -> Bool {
        normalizeRole(actual) == normalizeRole(wanted)
    }

    static func matchTitle(_ actual: String, _ wanted: String) -> Bool {
        actual.caseInsensitiveCompare(wanted) == .orderedSame
    }

    static func matches(role: String, title: String, wantRole: String?, wantTitle: String?) -> Bool {
        if wantRole == nil && wantTitle == nil { return false }
        if let wantRole, !matchRole(role, wantRole) { return false }
        if let wantTitle, !matchTitle(title, wantTitle) { return false }
        return true
    }

    static func js(id: Int32, role: String, title: String, value: String, frame: CGRect) -> [String: Any] {
        [
            "id": Int(id),
            "role": role,
            "title": title,
            "value": value,
            "frame": [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height,
            ] as [String: CGFloat],
        ]
    }
}

enum AXTree {
    static func string(_ el: AXUIElement, _ attr: CFString) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return "" }
        return (ref as? String) ?? ""
    }

    static func valueString(_ el: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &ref) == .success, let ref else {
            return ""
        }
        if let s = ref as? String { return s }
        if let n = ref as? NSNumber { return n.stringValue }
        return ""
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let kids = ref as? [AXUIElement] else {
            return []
        }
        return kids
    }

    static func parent(_ el: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &ref) == .success,
              let parent = ref else {
            return nil
        }
        return (parent as! AXUIElement)
    }

    static func focused() -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let el = ref else {
            return nil
        }
        return (el as! AXUIElement)
    }

    static func selectedText() -> String? {
        if let text = focusedSelectedText() { return text }
        guard enableWebContentAccessibility() else { return nil }
        // Chromium builds the tree on a background thread once asked, so the
        // first read after enabling usually still comes back empty.
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.05)
            if let text = focusedSelectedText() { return text }
        }
        return nil
    }

    private static func focusedSelectedText() -> String? {
        guard let el = focused() else { return nil }
        let text = string(el, kAXSelectedTextAttribute as CFString)
        return text.isEmpty ? nil : text
    }

    /// Chromium apps (Chrome, Edge, Electron) keep web-content accessibility off
    /// until a client asks for it, so a selection in a page reads as empty. Ask
    /// once per process; apps that do not support the attribute just say no.
    /// Reports whether this call was the one that turned the tree on.
    private static func enableWebContentAccessibility() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = app.processIdentifier
        guard !manualAccessibilityPIDs.contains(pid) else { return false }
        manualAccessibilityPIDs.insert(pid)
        let el = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return result == .success
    }

    // ponytail: no AXEnhancedUserInterface fallback for older Electron builds —
    // that flag breaks window resizing in native apps that also accept it.
    nonisolated(unsafe) private static var manualAccessibilityPIDs: Set<pid_t> = []

    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    static func setValue(_ el: AXUIElement, _ value: String) -> Bool {
        AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFString) == .success
    }

    static func find(role: String?, title: String?) -> AXUIElement? {
        guard role != nil || title != nil else { return nil }
        return walk(searchRoot(), role: role, title: title)
    }

    static func node(id: Int32, _ el: AXUIElement) -> [String: Any] {
        AXAttrs.js(
            id: id,
            role: string(el, kAXRoleAttribute as CFString),
            title: string(el, kAXTitleAttribute as CFString),
            value: valueString(el),
            frame: WindowAX.frame(el)
        )
    }

    private static func searchRoot() -> AXUIElement {
        if let app = NSWorkspace.shared.frontmostApplication {
            return AXUIElementCreateApplication(app.processIdentifier)
        }
        return AXUIElementCreateSystemWide()
    }

    private static func walk(_ el: AXUIElement, role: String?, title: String?) -> AXUIElement? {
        let actualRole = string(el, kAXRoleAttribute as CFString)
        let actualTitle = string(el, kAXTitleAttribute as CFString)
        if AXAttrs.matches(role: actualRole, title: actualTitle, wantRole: role, wantTitle: title) {
            return el
        }
        for child in children(el) {
            if let found = walk(child, role: role, title: title) { return found }
        }
        return nil
    }
}
