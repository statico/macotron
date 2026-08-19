// Spaces.swift — Mission Control spaces via SkyLight (dlsym)
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct SpaceInfo: Equatable, Sendable {
    public var id: UInt64
    public var index: Int
    public var desktop: Int
    public var display: String
    public var current: Bool
    public var type: String

    var js: [String: Any] {
        [
            "id": Int(id),
            "index": index,
            "desktop": desktop,
            "display": display,
            "current": current,
            "type": type,
        ]
    }
}

enum Spaces {
    static func typeName(_ raw: Int) -> String {
        switch raw {
        case 0: return "user"
        case 4: return "fullscreen"
        default: return "other"
        }
    }

    static func parse(_ raw: [[String: Any]]) -> [SpaceInfo] {
        var out: [SpaceInfo] = []
        var desktop = 1
        for display in raw {
            let uuid = string(display["Display Identifier"]) ?? ""
            let currentID = spaceID(dict(display["Current Space"]))
            let rows = display["Spaces"] as? [[String: Any]] ?? []
            for (i, row) in rows.enumerated() {
                let id = spaceID(row) ?? 0
                guard id != 0 else { continue }
                out.append(SpaceInfo(
                    id: id,
                    index: i + 1,
                    desktop: desktop,
                    display: uuid,
                    current: id == currentID,
                    type: typeName(int(row["type"]) ?? 0)
                ))
                desktop += 1
            }
        }
        return out
    }

    static func list() -> [SpaceInfo] {
        parse(SkyLight.copyManagedDisplaySpaces())
    }

    static func current() -> SpaceInfo? {
        list().first(where: \.current)
    }

    static func resolve(_ spec: Any) -> SpaceInfo? {
        let spaces = list()
        if let n = int(spec) {
            if let byID = spaces.first(where: { $0.id == UInt64(n) }) { return byID }
            if let byDesktop = spaces.first(where: { $0.desktop == n }) { return byDesktop }
            return nil
        }
        if let dict = spec as? [String: Any] {
            if let id = int(dict["id"]), let match = spaces.first(where: { $0.id == UInt64(id) }) {
                return match
            }
            let index = int(dict["index"])
            let display = string(dict["display"])
            return spaces.first {
                (index == nil || $0.index == index) && (display == nil || $0.display == display)
                    && (index != nil || display != nil)
            }
        }
        return nil
    }

    static func go(_ spec: Any) -> Bool {
        guard let space = resolve(spec) else { return false }
        return SkyLight.setCurrentSpace(display: space.display, id: space.id)
    }

    static func moveWindow(cgWindowID: CGWindowID, space: SpaceInfo) -> Bool {
        SkyLight.moveWindows([cgWindowID], to: space.id)
    }

    private static func spaceID(_ row: [String: Any]?) -> UInt64? {
        guard let row else { return nil }
        if let n = int(row["id64"]) { return UInt64(n) }
        if let n = int(row["ManagedSpaceID"]) { return UInt64(n) }
        return nil
    }

    private static func dict(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let i as Int64: return Int(i)
        case let i as UInt64: return Int(i)
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        default: return nil
        }
    }
}

enum SkyLight {
    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static func connectionID() -> Int32 {
        guard let fn = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self) else {
            return 0
        }
        return fn()
    }

    static func copyManagedDisplaySpaces() -> [[String: Any]] {
        let cid = connectionID()
        guard cid != 0,
              let fn = symbol("SLSCopyManagedDisplaySpaces", as: (@convention(c) (Int32) -> CFArray?).self),
              let cf = fn(cid) else {
            return []
        }
        return (cf as NSArray) as? [[String: Any]] ?? []
    }

    static func setCurrentSpace(display: String, id: UInt64) -> Bool {
        let cid = connectionID()
        guard cid != 0, !display.isEmpty,
              let fn = symbol(
                "SLSManagedDisplaySetCurrentSpace",
                as: (@convention(c) (Int32, CFString, UInt64) -> Void).self
              ) else {
            return false
        }
        fn(cid, display as CFString, id)
        return true
    }

    static func moveWindows(_ windowIDs: [CGWindowID], to space: UInt64) -> Bool {
        let cid = connectionID()
        guard cid != 0, !windowIDs.isEmpty,
              let fn = symbol(
                "SLSMoveWindowsToManagedSpace",
                as: (@convention(c) (Int32, CFArray, UInt64) -> Void).self
              ) else {
            return false
        }
        let nums = windowIDs.map { NSNumber(value: $0) } as NSArray
        fn(cid, nums, space)
        return true
    }
}
