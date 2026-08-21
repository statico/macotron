import ApplicationServices
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class DockModule: NativeModule {
    public let name = "dock"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let dock = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, dock, "badges", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if dockDryRun(ctx) { return JSBridge.newArray(ctx, []) }
            return JSBridge.newArray(ctx, DockBadges.list())
        }, "badges", 0))

        JS_SetPropertyStr(ctx, macotron, "dock", dock)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}

extension DockBadges {
    static func list() -> [Any] {
        guard AXIsProcessTrusted() else { return [] }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            return []
        }
        var tiles: [[String: Any]] = []
        collect(AXUIElementCreateApplication(pid), into: &tiles)
        return parse(tiles)
    }

    private static func collect(_ el: AXUIElement, into tiles: inout [[String: Any]]) {
        let role = AXTree.string(el, kAXRoleAttribute as CFString)
        if isTile(role) {
            let title = AXTree.string(el, kAXTitleAttribute as CFString)
            var tile: [String: Any] = [
                "title": title,
                "attributes": attributes(el),
            ]
            if let bid = bundleID(el) { tile["bundleID"] = bid }
            tiles.append(tile)
        }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let kids = ref as? [AXUIElement] else { return }
        for child in kids { collect(child, into: &tiles) }
    }

    private static func isTile(_ role: String) -> Bool {
        let r = role.lowercased()
        return r.contains("dockitem") || r.contains("dockextra")
    }

    private static func attributes(_ el: AXUIElement) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in ["AXStatusLabel", "AXBadgeDescription"] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, key as CFString, &ref) == .success, let ref {
                out[key] = ref
            }
        }
        return out
    }

    private static func bundleID(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &ref) == .success else { return nil }
        let url = (ref as? URL) ?? (ref as? NSURL).map { $0 as URL }
        guard let url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

@MainActor
private func dockDryRun(_ ctx: OpaquePointer) -> Bool {
    guard let opaque = JS_GetContextOpaque(ctx) else { return false }
    return Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue().dryRun
}
