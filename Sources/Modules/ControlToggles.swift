import Darwin
import Foundation
import Intents
import IOBluetooth

enum NetworkControl {
    static func wifiDevice(from text: String) -> String? {
        var wantDevice = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("hardware port:") {
                let name = value(line)
                wantDevice = name.localizedCaseInsensitiveContains("wi-fi")
                    || name.localizedCaseInsensitiveContains("airport")
            } else if wantDevice, line.lowercased().hasPrefix("device:") {
                let device = value(line)
                return device.isEmpty ? nil : device
            }
        }
        return nil
    }

    static func parsePower(_ text: String) -> Bool? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasSuffix(": on") { return true }
        if t.hasSuffix(": off") { return false }
        return nil
    }

    static func parseSSID(_ text: String) -> String? {
        let out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out.localizedCaseInsensitiveContains("not associated") {
            return nil
        }
        guard let range = out.range(of: ": ") else { return nil }
        let ssid = String(out[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ssid.isEmpty ? nil : ssid
    }

    static func parseAirDrop(_ raw: String?) -> String {
        guard let raw, let plist = airDropPlistValue(raw) else { return "off" }
        switch plist {
        case "Everyone": return "everyone"
        case "Contacts Only": return "contacts"
        default: return "off"
        }
    }

    static func airDropPlistValue(_ mode: String) -> String? {
        switch mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "off", "none", "no": return "Off"
        case "contacts", "contacts only", "people": return "Contacts Only"
        case "everyone", "all": return "Everyone"
        default: return nil
        }
    }

    static func wifi() -> [String: Any] {
        guard let device = wifiDevice() else {
            return ["available": false, "on": false]
        }
        var snap: [String: Any] = [
            "available": true,
            "on": power(device) ?? false,
        ]
        if let ssid = ssid(device) {
            snap["ssid"] = ssid
        }
        return snap
    }

    static func currentSSID() -> String? {
        guard let device = wifiDevice() else { return nil }
        return ssid(device)
    }

    static func setWifi(_ on: Bool, dryRun: Bool) -> [String: Any] {
        if dryRun {
            return ["ok": true, "available": true, "on": on]
        }
        guard let device = wifiDevice() else {
            return ["ok": false, "available": false, "on": false, "error": "No Wi-Fi hardware"]
        }
        let result = run("/usr/sbin/networksetup", ["-setairportpower", device, on ? "on" : "off"])
        var snap = wifi()
        snap["ok"] = result.ok
        if !result.ok {
            snap["error"] = result.out.isEmpty ? "Could not change Wi-Fi" : result.out
        }
        return snap
    }

    static func airDrop() -> [String: Any] {
        let raw = UserDefaults(suiteName: "com.apple.sharingd")?.string(forKey: "DiscoverableMode")
        return ["mode": parseAirDrop(raw)]
    }

    static func setAirDrop(_ mode: String, dryRun: Bool) -> [String: Any] {
        guard let value = airDropPlistValue(mode) else {
            return [
                "ok": false,
                "mode": airDrop()["mode"] as? String ?? "off",
                "error": "mode must be off, contacts, or everyone",
            ]
        }
        let normalized = parseAirDrop(value)
        if dryRun {
            return ["ok": true, "mode": normalized]
        }
        UserDefaults(suiteName: "com.apple.sharingd")?.set(value, forKey: "DiscoverableMode")
        _ = run("/usr/bin/killall", ["sharingd"])
        return ["ok": true, "mode": normalized]
    }

    private static func wifiDevice() -> String? {
        wifiDevice(from: run("/usr/sbin/networksetup", ["-listallhardwareports"]).out)
    }

    private static func power(_ device: String) -> Bool? {
        parsePower(run("/usr/sbin/networksetup", ["-getairportpower", device]).out)
    }

    private static func ssid(_ device: String) -> String? {
        parseSSID(run("/usr/sbin/networksetup", ["-getairportnetwork", device]).out)
    }

    private static func value(_ line: String) -> String {
        guard let range = line.range(of: ":") else { return "" }
        return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    static func ping(_ host: String = "1.1.1.1") -> [String: Any] {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = target.isEmpty ? "1.1.1.1" : target
        let result = run("/sbin/ping", ["-c", "1", "-t", "2", dest])
        if let ms = NetworkPing.parse(result.out) {
            return ["ms": ms, "host": dest]
        }
        let line = result.out.split(separator: "\n").first.map(String.init) ?? ""
        return [
            "ms": NSNull(),
            "host": dest,
            "error": line.isEmpty ? "ping failed" : line,
        ]
    }

    private static func run(_ path: String, _ args: [String]) -> (out: String, ok: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", false)
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (out, process.terminationStatus == 0)
    }
}

enum NetworkPing {
    static func parse(_ stdout: String) -> Double? {
        guard let range = stdout.range(of: "time=") else { return nil }
        let num = stdout[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." })
        return Double(num)
    }
}

enum NetworkRate {
    static func format(_ bps: Double) -> String {
        let n = abs(bps)
        if n < 1_000 { return String(Int(n.rounded())) }
        let (div, suffix): (Double, String) =
            n < 1_000_000 ? (1_000, "K")
            : n < 1_000_000_000 ? (1_000_000, "M")
            : (1_000_000_000, "G")
        let scaled = n / div
        if scaled >= 10 || abs(scaled - scaled.rounded()) < 0.05 {
            return String(Int(scaled.rounded())) + suffix
        }
        return String(format: "%.1f", scaled) + suffix
    }
}

enum BluetoothRadio {
    /// `batteries` comes from `BluetoothBattery.cached()`, which shells out to
    /// system_profiler for over a second. The caller fetches it off the main
    /// thread and hands it in, leaving this a cheap IOBluetooth query.
    static func snapshot(batteries: [String: Int]) -> [String: Any] {
        ["on": isOn(), "devices": devices(batteries)]
    }

    static func set(_ on: Bool, dryRun: Bool) -> [String: Any] {
        if dryRun {
            return ["ok": true, "on": on]
        }
        guard let setPower = powerSet else {
            return ["ok": false, "on": isOn(), "error": "Bluetooth power is unavailable"]
        }
        setPower(on ? 1 : 0)
        return ["ok": true, "on": on]
    }

    private static func isOn() -> Bool {
        powerGet?() == 1
    }

    private static func devices(_ batteries: [String: Int]) -> [Any] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return paired.map { device -> [String: Any] in
            let name = device.name ?? device.addressString ?? ""
            let address = device.addressString ?? ""
            var row: [String: Any] = [
                "name": name,
                "address": address,
                "connected": device.isConnected(),
            ]
            if let pct = batteries[name] ?? batteries[BluetoothBattery.normalize(address)] {
                row["battery"] = pct
            } else {
                row["battery"] = NSNull()
            }
            return row
        }
    }

    private static let powerGet: (@convention(c) () -> Int32)? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth",
            RTLD_LAZY
        ), let sym = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
    }()

    private static let powerSet: (@convention(c) (Int32) -> Void)? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth",
            RTLD_LAZY
        ), let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (Int32) -> Void).self)
    }()
}

enum BluetoothBattery {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: (at: Date, map: [String: Int])?

    static func cached() -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        if let cache, Date().timeIntervalSince(cache.at) < 30 { return cache.map }
        let map = parse(profilerJSON())
        self.cache = (Date(), map)
        return map
    }

    static func parse(_ json: Data) -> [String: Int] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let list = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return [:]
        }
        var map: [String: Int] = [:]
        for controller in list {
            ingest(controller["device_connected"], into: &map)
            ingest(controller["device_not_connected"], into: &map)
        }
        return map
    }

    static func normalize(_ address: String) -> String {
        address.replacingOccurrences(of: ":", with: "-").lowercased()
    }

    private static func ingest(_ raw: Any?, into map: inout [String: Int]) {
        guard let rows = raw as? [[String: Any]] else { return }
        for row in rows {
            for (name, value) in row {
                guard let props = value as? [String: Any], let pct = percent(props) else { continue }
                map[name] = pct
                if let addr = props["device_address"] as? String {
                    map[normalize(addr)] = pct
                }
            }
        }
    }

    private static func percent(_ props: [String: Any]) -> Int? {
        var levels: [Int] = []
        for (key, value) in props {
            let k = key.lowercased()
            guard k.contains("batterylevel") || k.contains("batterypercent") else { continue }
            if let n = parsePercent(value) { levels.append(n) }
        }
        return levels.min()
    }

    private static func parsePercent(_ value: Any) -> Int? {
        if let n = value as? Int { return min(100, max(0, n)) }
        if let n = value as? Double { return min(100, max(0, Int(n.rounded()))) }
        let text = String(describing: value)
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let n = Double(text) else { return nil }
        return min(100, max(0, Int(n.rounded())))
    }

    private static func profilerJSON() -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return Data()
        }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

enum DarkMode {
    static func parse(_ text: String) -> Bool? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes": return true
        case "false", "no": return false
        default: return nil
        }
    }

    static func isOn() -> Bool {
        if let get = themeGet { return get() }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func set(_ on: Bool, dryRun: Bool) -> [String: Any] {
        if dryRun {
            return ["ok": true, "darkMode": on]
        }
        if let setTheme = themeSet {
            setTheme(on)
            return ["ok": true, "darkMode": on]
        }
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let err = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["ok": false, "darkMode": isOn(), "error": error.localizedDescription]
        }
        if process.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return [
                "ok": false,
                "darkMode": isOn(),
                "error": msg.isEmpty ? "Could not change appearance" : msg,
            ]
        }
        return ["ok": true, "darkMode": on]
    }

    private static let themeGet: (@convention(c) () -> Bool)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ), let sym = dlsym(handle, "SLSGetAppearanceThemeLegacy") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) () -> Bool).self)
    }()

    private static let themeSet: (@convention(c) (Bool) -> Void)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        ), let sym = dlsym(handle, "SLSSetAppearanceThemeLegacy") else {
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) (Bool) -> Void).self)
    }()
}

enum FocusStatus {
    static func snapshot() -> [String: Any] {
        // isFocused is nil until the user grants Focus status sharing.
        ["focused": INFocusStatusCenter.default.focusStatus.isFocused ?? false]
    }
}
