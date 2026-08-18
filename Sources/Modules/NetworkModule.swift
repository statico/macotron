// NetworkModule.swift — macotron.network: Wi-Fi SSID, interfaces, wifi:changed
import CQuickJS
import Darwin
import Foundation
import MacotronEngine

@MainActor
public final class NetworkModule: NativeModule {
    public let name = "network"

    private weak var engine: Engine?
    private var timer: Timer?
    private var lastSSID: String?

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__networkModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let network = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, network, "wifiSSID", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            if let ssid = NetworkModule.currentSSID() {
                return JSBridge.newString(ctx, ssid)
            }
            return QJS_Null()
        }, "wifiSSID", 0))

        JS_SetPropertyStr(ctx, network, "interfaces", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newArray(ctx, NetworkModule.ipv4Interfaces())
        }, "interfaces", 0))

        JS_SetPropertyStr(ctx, macotron, "network", network)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        lastSSID = NetworkModule.currentSSID()
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
        let ssid = NetworkModule.currentSSID()
        guard ssid != lastSSID else { return }
        lastSSID = ssid
        guard let engine, let ctx = engine.context else { return }

        let data = JS_NewObject(ctx)
        if let ssid {
            JS_SetPropertyStr(ctx, data, "ssid", JSBridge.newString(ctx, ssid))
        } else {
            JS_SetPropertyStr(ctx, data, "ssid", QJS_Null())
        }
        engine.eventBus.emit("wifi:changed", engine: engine, data: data)
        JS_FreeValue(ctx, data)
    }

    // ponytail: Process fallback — CoreWLAN often fails to link under SPM
    private static func currentSSID() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getairportnetwork", "en0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if out.isEmpty || out.localizedCaseInsensitiveContains("not associated") {
            return nil
        }
        guard let range = out.range(of: ": ") else { return nil }
        let ssid = String(out[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ssid.isEmpty ? nil : ssid
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
}
