import Darwin
import Foundation
import ObjectiveC

enum DisplayAppearance {
    struct NightShiftRequest: Equatable {
        var on: Bool
        var strength: Double?
    }

    static func parseNightShift(_ value: Any) -> NightShiftRequest? {
        if let on = value as? Bool {
            return NightShiftRequest(on: on, strength: nil)
        }
        guard let obj = value as? [String: Any] else { return nil }
        let strength = number(obj["strength"]).map { min(1, max(0, $0)) }
        let on = obj["on"] as? Bool ?? true
        return NightShiftRequest(on: on, strength: strength)
    }

    static func nightShift() -> [String: Any] {
        guard let client = blueLightClient() else { return unavailable() }
        var result: [String: Any] = ["on": blueLightEnabled(client), "available": true]
        if let strength = getStrength(client) { result["strength"] = Double(strength) }
        return result
    }

    static func setNightShift(_ req: NightShiftRequest) -> [String: Any] {
        guard let client = blueLightClient() else {
            return setFail("Night Shift unavailable")
        }
        if let strength = req.strength {
            _ = setStrength(client, Float(strength))
        }
        guard setEnabled(client, req.on) == true else {
            return setFail("Night Shift failed")
        }
        var result = nightShift()
        result["ok"] = true
        return result
    }

    static func trueTone() -> [String: Any] {
        guard let client = trueToneClient() else { return unavailable() }
        return ["on": boolProp(client, "enabled") ?? false, "available": true]
    }

    static func setTrueTone(_ on: Bool) -> [String: Any] {
        guard let client = trueToneClient() else {
            return setFail("True Tone unavailable")
        }
        guard setEnabled(client, on) == true else {
            return setFail("True Tone failed")
        }
        return ["ok": true, "on": boolProp(client, "enabled") ?? on, "available": true]
    }

    static func grayscale() -> [String: Any] {
        guard let uses = grayFns.uses else { return unavailable() }
        return ["on": uses() != 0, "available": true]
    }

    static func setGrayscale(_ on: Bool) -> [String: Any] {
        guard let set = grayFns.force else {
            return setFail("grayscale unavailable")
        }
        set(on ? 1 : 0)
        return ["ok": true, "on": grayFns.uses.map { $0() != 0 } ?? on, "available": true]
    }

    private static func unavailable() -> [String: Any] {
        ["on": false, "available": false]
    }

    static func setFail(_ error: String) -> [String: Any] {
        ["ok": false, "on": false, "available": false, "error": error]
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let i as Int32: return Double(i)
        default: return nil
        }
    }

    private typealias ForceGray = @convention(c) (UInt8) -> Void
    private typealias UsesGray = @convention(c) () -> UInt8

    private static let grayFns: (force: ForceGray?, uses: UsesGray?) = {
        func load(_ handle: UnsafeMutableRawPointer?) -> (ForceGray?, UsesGray?) {
            (
                dlsym(handle, "CGDisplayForceToGray").map { unsafeBitCast($0, to: ForceGray.self) },
                dlsym(handle, "CGDisplayUsesForceToGray").map { unsafeBitCast($0, to: UsesGray.self) }
            )
        }
        return load(dlopen(nil, RTLD_LAZY))
    }()

    @discardableResult
    private static func loadCoreBrightness() -> Bool {
        dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_LAZY
        ) != nil
    }

    private static func blueLightClient() -> NSObject? {
        client(named: "CBBlueLightClient")
    }

    private static func trueToneClient() -> NSObject? {
        client(named: "CBTrueToneClient") ?? client(named: "CBAdaptationClient")
    }

    private static func client(named name: String) -> NSObject? {
        _ = loadCoreBrightness()
        guard let cls = NSClassFromString(name) as? NSObject.Type else { return nil }
        return cls.init()
    }

    private static func blueLightEnabled(_ client: NSObject) -> Bool {
        if let on = boolOut(client, "getEnabled:") { return on }
        var buf = [UInt8](repeating: 0, count: 128)
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel), let method = client.method(for: sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ptr = raw.baseAddress else { return false }
            return unsafeBitCast(method, to: Fn.self)(client, sel, ptr)
        }
        return ok && buf.count > 1 && buf[1] != 0
    }

    private static func getStrength(_ client: NSObject) -> Float? {
        let sel = NSSelectorFromString("getStrength:")
        guard client.responds(to: sel), let method = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> Bool
        var value: Float = 0
        return unsafeBitCast(method, to: Fn.self)(client, sel, &value) ? value : nil
    }

    private static func setStrength(_ client: NSObject, _ value: Float) -> Bool? {
        let sel = NSSelectorFromString("setStrength:commit:")
        guard client.responds(to: sel), let method = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
        return unsafeBitCast(method, to: Fn.self)(client, sel, value, true)
    }

    private static func setEnabled(_ client: NSObject, _ on: Bool) -> Bool? {
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel), let method = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        return unsafeBitCast(method, to: Fn.self)(client, sel, on)
    }

    private static func boolProp(_ client: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel), let method = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method, to: Fn.self)(client, sel)
    }

    private static func boolOut(_ client: NSObject, _ name: String) -> Bool? {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel), let method = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Bool>) -> Bool
        var value = false
        return unsafeBitCast(method, to: Fn.self)(client, sel, &value) ? value : nil
    }
}
