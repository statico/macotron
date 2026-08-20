// WindowAX.swift — AX helpers shared by window, spaces, and watchers
import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation

enum WindowAX {
    static func windowID(pid: pid_t, index: Int) -> Int32 {
        Int32(pid) * 1000 + Int32(index)
    }

    static func resolve(id: Int32) -> AXUIElement? {
        let pid = pid_t(id / 1000)
        let index = Int(id % 1000)
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return nil }
        guard index >= 0, index < windows.count else { return nil }
        return windows[index]
    }

    static func frame(_ win: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var origin = CGPoint.zero
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
           let posRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        }
        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    static func title(_ win: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String else {
            return ""
        }
        return title
    }

    static func index(of win: AXUIElement, pid: pid_t) -> Int {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return 0
        }
        let wantTitle = title(win)
        for (i, other) in windows.enumerated() where title(other) == wantTitle {
            return i
        }
        return 0
    }

    static func info(_ win: AXUIElement, pid: pid_t, app: String) -> [String: Any] {
        let i = index(of: win, pid: pid)
        return [
            "id": Int(windowID(pid: pid, index: i)),
            "title": title(win),
            "app": app,
        ]
    }

    static func setBool(_ win: AXUIElement, _ attr: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(
            win,
            attr as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success
    }

    static func minimize(_ id: Int32, _ on: Bool) -> Bool {
        guard let win = resolve(id: id) else { return false }
        return setBool(win, kAXMinimizedAttribute as String, on)
    }

    static func setFullscreen(_ id: Int32, _ on: Bool) -> Bool {
        guard let win = resolve(id: id) else { return false }
        return setBool(win, "AXFullScreen", on)
    }

    static func close(_ id: Int32) -> Bool {
        guard let win = resolve(id: id) else { return false }
        var buttonRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
              let button = buttonRef else {
            return false
        }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    static func cgWindowID(_ id: Int32) -> CGWindowID? {
        guard let win = resolve(id: id) else { return nil }
        typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        guard let handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY
        ), let sym = dlsym(handle, "_AXUIElementGetWindow") else {
            return nil
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        var cgID: CGWindowID = 0
        return fn(win, &cgID) == .success ? cgID : nil
    }
}
