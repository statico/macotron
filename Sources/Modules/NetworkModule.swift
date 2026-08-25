// NetworkModule.swift — macotron.network: Wi-Fi, Bluetooth, AirDrop, interfaces
import CQuickJS
import Darwin
import Foundation
import MacotronEngine

@MainActor
public final class NetworkModule: NativeModule {
    public let name = "network"
    public let moduleVersion = 2

    private weak var engine: Engine?
    private var timer: Timer?
    private var lastWifi: (on: Bool, ssid: String?)?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__networkModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let network = JS_NewObject(ctx)

        // networksetup is three subprocesses deep for a full Wi-Fi snapshot, so
        // every reader of it hands back a promise rather than stalling the menu.
        JS_SetPropertyStr(ctx, network, "wifiSSID", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: NSNull()) {
                .of(NetworkControl.currentSSID())
            }
        }, "wifiSSID", 0))

        JS_SetPropertyStr(ctx, network, "wifi", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: NetworkModule.noWifi) {
                .value(NetworkControl.wifi())
            }
        }, "wifi", 0))

        JS_SetPropertyStr(ctx, network, "setWifi", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let on = JSBridge.toBool(ctx, argv[0])
            return JSBridge.promise(ctx, dryRun: NetworkControl.setWifi(on, dryRun: true)) {
                .value(NetworkControl.setWifi(on, dryRun: false))
            }
        }, "setWifi", 1))

        JS_SetPropertyStr(ctx, network, "bluetooth", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.promise(ctx, dryRun: NetworkModule.noBluetooth) {
                let batteries = BluetoothBattery.cached()
                // The paired-device list is an IOBluetooth query that wants the
                // main thread; it is cheap once the batteries are already read.
                return .value(DispatchQueue.main.sync {
                    BluetoothRadio.snapshot(batteries: batteries)
                })
            }
        }, "bluetooth", 0))

        // Flipping the radio is a dlsym'd IOBluetooth call, not a subprocess:
        // it stays synchronous.
        JS_SetPropertyStr(ctx, network, "setBluetooth", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let on = JSBridge.toBool(ctx, argv[0])
            return JSBridge.newObject(ctx, BluetoothRadio.set(on, dryRun: NetworkModule.dryRun(ctx)))
        }, "setBluetooth", 1))

        // Reading the mode is a defaults lookup; only writing it has to kill
        // sharingd, so only the setter is a promise.
        JS_SetPropertyStr(ctx, network, "airDrop", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, NetworkControl.airDrop())
        }, "airDrop", 0))

        JS_SetPropertyStr(ctx, network, "setAirDrop", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1 else { return QJS_Undefined() }
            let mode = JSBridge.toString(ctx, argv[0]) ?? ""
            return JSBridge.promise(ctx, dryRun: NetworkControl.setAirDrop(mode, dryRun: true)) {
                .value(NetworkControl.setAirDrop(mode, dryRun: false))
            }
        }, "setAirDrop", 1))

        JS_SetPropertyStr(ctx, network, "interfaces", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, NetworkModule.ipv4Interfaces())
        }, "interfaces", 0))

        JS_SetPropertyStr(ctx, network, "counters", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, NetworkModule.counters())
        }, "counters", 0))

        JS_SetPropertyStr(ctx, network, "ping", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx else { return QJS_Undefined() }
            var host = "1.1.1.1"
            if argc >= 1, let argv, let given = JSBridge.toString(ctx, argv[0]), !given.isEmpty {
                host = given
            }
            let target = host
            return JSBridge.promise(ctx, dryRun: ["ms": NSNull(), "host": target] as [String: Any]) {
                .value(NetworkControl.ping(target))
            }
        }, "ping", 1))

        JS_SetPropertyStr(ctx, macotron, "network", network)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    public func cleanup() {
        timer?.invalidate()
        timer = nil
        engine = nil
    }

    private func poll() {
        // Sampling costs three networksetup runs; on main that is a stutter
        // every five seconds for a value that rarely changes.
        DispatchQueue.global(qos: .utility).async {
            let key = NetworkModule.wifiKey()
            Task { @MainActor [weak self] in self?.emit(key) }
        }
    }

    private func emit(_ key: (on: Bool, ssid: String?)) {
        // The first sample is only the seed later ones are compared against.
        guard let last = lastWifi else {
            lastWifi = key
            return
        }
        if last.on == key.on, last.ssid == key.ssid { return }
        lastWifi = key
        guard let engine, let ctx = engine.context else { return }

        let data = JS_NewObject(ctx)
        JS_SetPropertyStr(ctx, data, "on", JSBridge.newBool(ctx, key.on))
        if let ssid = key.ssid {
            JS_SetPropertyStr(ctx, data, "ssid", JSBridge.newString(ctx, ssid))
        } else {
            JS_SetPropertyStr(ctx, data, "ssid", QJS_Null())
        }
        engine.eventBus.emit("wifi:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }

    /// What `--check` sees instead of a real radio: the same shape the host
    /// returns on a Mac with no Wi-Fi or Bluetooth hardware.
    private static let noWifi: [String: Any] = ["available": false, "on": false]
    private static let noBluetooth: [String: Any] = ["on": false, "devices": [Any]()]

    /// nonisolated: this only shells out to networksetup, and the 5s poll
    /// samples it from a background queue.
    private nonisolated static func wifiKey() -> (on: Bool, ssid: String?) {
        let snap = NetworkControl.wifi()
        return (snap["on"] as? Bool ?? false, snap["ssid"] as? String)
    }

    private static func dryRun(_ ctx: OpaquePointer) -> Bool {
        let opaque = JS_GetContextOpaque(ctx)
        return opaque.map { Unmanaged<Engine>.fromOpaque($0).takeUnretainedValue().dryRun } ?? false
    }

    private static func ipv4Interfaces() -> [Any] {
        var result: [Any] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            let flags = Int32(iface.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0,
                  let addr = iface.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(addr.pointee.sa_len)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = host.withUnsafeBufferPointer { buf in
                String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            result.append([
                "name": String(cString: iface.pointee.ifa_name),
                "ip": ip,
            ] as [String: Any])
        }
        return result
    }

    private static func counters() -> [Any] {
        var byName: [String: (ip: String?, bytesIn: Int, bytesOut: Int)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr {
            defer { ptr = iface.pointee.ifa_next }
            let flags = Int32(iface.pointee.ifa_flags)
            let name = String(cString: iface.pointee.ifa_name)
            if name == "lo0" || (flags & IFF_LOOPBACK) != 0 { continue }
            guard let addr = iface.pointee.ifa_addr else { continue }
            var cur = byName[name] ?? (nil, 0, 0)
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = iface.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                cur.bytesIn = Int(stats.ifi_ibytes)
                cur.bytesOut = Int(stats.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET), cur.ip == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let len = socklen_t(addr.pointee.sa_len)
                if getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    cur.ip = host.withUnsafeBufferPointer { buf in
                        String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    }
                }
            }
            byName[name] = cur
        }
        return byName.keys.sorted().map { name -> [String: Any] in
            let cur = byName[name]!
            var row: [String: Any] = [
                "name": name,
                "bytesIn": cur.bytesIn,
                "bytesOut": cur.bytesOut,
            ]
            if let ip = cur.ip { row["ip"] = ip }
            return row
        }
    }
}
