// SystemModule.swift — macotron.system: CPU temp, memory, battery info
import CQuickJS
import Darwin
import Foundation
import MacotronEngine
import IOKit
import IOKit.ps
import Metal
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "system")

enum CPULoad {
    static func percent(from prev: host_cpu_load_info, to now: host_cpu_load_info) -> Double {
        let user = Double(now.cpu_ticks.0) - Double(prev.cpu_ticks.0)
        let system = Double(now.cpu_ticks.1) - Double(prev.cpu_ticks.1)
        let idle = Double(now.cpu_ticks.2) - Double(prev.cpu_ticks.2)
        let nice = Double(now.cpu_ticks.3) - Double(prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return ((user + system + nice) / total) * 100
    }
}

private final class CPUTicks: @unchecked Sendable {
    let lock = NSLock()
    var prev: host_cpu_load_info?
    static let shared = CPUTicks()

    func usage() -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let now = Self.sample() else { return 0 }
        let last = prev
        prev = now
        guard let last else { return 0 }
        return CPULoad.percent(from: last, to: now)
    }

    static func sample() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }
}

enum BatteryStatus {
    static func snapshot(_ sources: [[String: Any]]) -> [String: Any] {
        var level: Double = -1
        var charging = false
        var charged = false
        var timeRemaining = -1
        var timeToFull = -1
        for desc in sources {
            let capacity = int(desc[kIOPSCurrentCapacityKey])
            let maxCapacity = int(desc[kIOPSMaxCapacityKey])
            if let capacity, let maxCapacity, maxCapacity > 0 {
                level = Double(capacity) / Double(maxCapacity) * 100.0
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                charging = (state == kIOPSACPowerValue)
            }
            if let flag = desc[kIOPSIsChargedKey] as? Bool {
                charged = flag
            } else if let n = desc[kIOPSIsChargedKey] as? NSNumber {
                charged = n.boolValue
            }
            if let minutes = int(desc[kIOPSTimeToEmptyKey]), minutes >= 0 {
                timeRemaining = minutes
            }
            if let minutes = int(desc[kIOPSTimeToFullChargeKey]), minutes >= 0 {
                timeToFull = minutes
            }
        }
        return [
            "level": level,
            "charging": charging,
            "charged": charged,
            "timeRemaining": timeRemaining,
            "timeToFull": timeToFull,
        ]
    }

    static func current() -> [String: Any] {
        var sources: [[String: Any]] = []
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any] {
            for source in list {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any] {
                    sources.append(desc)
                }
            }
        }
        return snapshot(sources)
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}

enum GPUStats {
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }
            for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
                if let n = stats[key] as? NSNumber { return n.doubleValue }
            }
        }
        return nil
    }
}

@MainActor
public final class SystemModule: NativeModule {
    public let name = "system"

    public init() {}

    public func cleanup() {
        FanController.shared.restoreIfNeeded()
    }

    public func register(in engine: Engine, options: [String: Any]) {
        Permissions.beforeFanHelperUnregister = { FanController.shared.restoreIfNeeded() }
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let systemObj = JS_NewObject(ctx)

        _ = CPUTicks.shared.usage()

        JS_SetPropertyStr(ctx, systemObj, "cpuTemp",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newFloat64(ctx, 0.0)
        }, "cpuTemp", 0))

        JS_SetPropertyStr(ctx, systemObj, "cpu",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, ["usage": CPUTicks.shared.usage()])
        }, "cpu", 0))

        JS_SetPropertyStr(ctx, systemObj, "locale",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let loc = Locale.current
            let metric = loc.measurementSystem == .metric
            return JSBridge.newObject(ctx, [
                "language": loc.language.languageCode?.identifier ?? "",
                "region": loc.region?.identifier ?? "",
                "measurement": metric ? "metric" : "us",
            ])
        }, "locale", 0))

        // macotron.system.memory() -> {total, used, free}
        JS_SetPropertyStr(ctx, systemObj, "memory",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            let pageSize = UInt64(getpagesize())
            let totalMemory = ProcessInfo.processInfo.physicalMemory

            var stats = vm_statistics64()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
            )

            let result = withUnsafeMutablePointer(to: &stats) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    host_statistics64(
                        mach_host_self(),
                        HOST_VM_INFO64,
                        intPtr,
                        &count
                    )
                }
            }

            if result != KERN_SUCCESS {
                logger.error("Failed to get memory stats: \(result)")
                return JSBridge.newObject(ctx, [
                    "total": Double(totalMemory),
                    "used": 0.0,
                    "free": Double(totalMemory)
                ])
            }

            let activeBytes = UInt64(stats.active_count) * UInt64(pageSize)
            let inactiveBytes = UInt64(stats.inactive_count) * UInt64(pageSize)
            let wiredBytes = UInt64(stats.wire_count) * UInt64(pageSize)
            let compressedBytes = UInt64(stats.compressor_page_count) * UInt64(pageSize)

            let usedBytes = activeBytes + wiredBytes + compressedBytes
            let freeBytes = totalMemory - usedBytes

            return JSBridge.newObject(ctx, [
                "total": Double(totalMemory),
                "used": Double(usedBytes),
                "free": Double(freeBytes),
                "active": Double(activeBytes),
                "inactive": Double(inactiveBytes),
                "wired": Double(wiredBytes),
                "compressed": Double(compressedBytes)
            ])
        }, "memory", 0))

        JS_SetPropertyStr(ctx, systemObj, "battery",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, BatteryStatus.current())
        }, "battery", 0))

        // macotron.system.disk() -> {total, free, used}
        JS_SetPropertyStr(ctx, systemObj, "disk",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            let total = Double(values?.volumeTotalCapacity ?? 0)
            let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0)

            return JSBridge.newObject(ctx, [
                "total": total,
                "free": free,
                "used": max(0, total - free)
            ])
        }, "disk", 0))

        // macotron.system.network() -> {bytesIn, bytesOut}
        JS_SetPropertyStr(ctx, systemObj, "network",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var bytesIn: UInt64 = 0
            var bytesOut: UInt64 = 0
            var ifaddr: UnsafeMutablePointer<ifaddrs>?
            if getifaddrs(&ifaddr) == 0, let first = ifaddr {
                defer { freeifaddrs(ifaddr) }
                var ptr: UnsafeMutablePointer<ifaddrs>? = first
                while let cur = ptr {
                    let name = String(cString: cur.pointee.ifa_name)
                    if name != "lo0",
                       let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                       let data = cur.pointee.ifa_data {
                        let ifd = data.assumingMemoryBound(to: if_data.self)
                        bytesIn += UInt64(ifd.pointee.ifi_ibytes)
                        bytesOut += UInt64(ifd.pointee.ifi_obytes)
                    }
                    ptr = cur.pointee.ifa_next
                }
            }

            return JSBridge.newObject(ctx, [
                "bytesIn": Double(bytesIn),
                "bytesOut": Double(bytesOut)
            ])
        }, "network", 0))

        // macotron.system.processes(limit?) -> [{name, pid, cpu}]
        JS_SetPropertyStr(ctx, systemObj, "processes",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var limit = 10
            if let argv, argc > 0, !JS_IsUndefined(argv[0]), !JS_IsNull(argv[0]) {
                limit = max(0, Int(JSBridge.toInt32(ctx, argv[0])))
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/ps")
            proc.arguments = ["-Ao", "pid,pcpu,comm", "-r"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return JSBridge.newArray(ctx, [])
            }

            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var results: [Any] = []
            for line in text.split(separator: "\n").dropFirst() {
                if results.count >= limit { break }
                let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard parts.count >= 3,
                      let pid = Int(parts[0]),
                      let cpu = Double(parts[1]) else { continue }
                results.append([
                    "name": parts.dropFirst(2).joined(separator: " "),
                    "pid": pid,
                    "cpu": cpu
                ] as [String: Any])
            }
            return JSBridge.newArray(ctx, results)
        }, "processes", 1))

        JS_SetPropertyStr(ctx, systemObj, "gpu",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let name = MTLCreateSystemDefaultDevice()?.name else { return QJS_Null() }
            return JSBridge.newObject(ctx, [
                "name": name,
                "usage": GPUStats.utilization() ?? 0,
            ])
        }, "gpu", 0))

        JS_SetPropertyStr(ctx, systemObj, "fans",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, FanController.shared.snapshot().js)
        }, "fans", 0))

        JS_SetPropertyStr(ctx, systemObj, "setFanFloor",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            var percent: Int?
            if let argv, argc >= 1, !JSBridge.isUndefined(argv[0]), !JS_IsNull(argv[0]) {
                percent = Int(JSBridge.toInt32(ctx, argv[0]))
            }
            let opaque = JS_GetContextOpaque(ctx)
            let dryRun = opaque.map { Unmanaged<Engine>.fromOpaque($0).takeUnretainedValue().dryRun } ?? false
            return JSBridge.newObject(ctx, FanController.shared.setFloor(percent, dryRun: dryRun).js)
        }, "setFanFloor", 1))

        JS_SetPropertyStr(ctx, macotron, "system", systemObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
