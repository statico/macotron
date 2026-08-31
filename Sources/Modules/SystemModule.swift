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

/// Per-core load split by core type. Apple Silicon enumerates the efficiency
/// cluster first, so the last `hw.perflevel0.logicalcpu` cores are the
/// performance ones; Intel reports a single perf level and lands all in
/// `performance`.
enum CoreTopology {
    static func count(_ name: String) -> Int {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return value
    }

    /// (efficiency, performance) logical core counts.
    static let split: (efficiency: Int, performance: Int) = {
        let total = count("hw.logicalcpu")
        let performance = count("hw.perflevel0.logicalcpu")
        guard count("hw.nperflevels") > 1, performance > 0, performance < total else {
            return (0, total)
        }
        return (total - performance, performance)
    }()
}

private final class CoreTicks: @unchecked Sendable {
    static let shared = CoreTicks()
    private let lock = NSLock()
    private var prev: [[Double]]?

    /// Busy percent for the efficiency and performance clusters.
    func usage() -> (efficiency: Double, performance: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard let now = Self.sample() else { return (0, 0) }
        let last = prev
        prev = now
        guard let last, last.count == now.count else { return (0, 0) }

        let eCount = min(CoreTopology.split.efficiency, now.count)
        func busy(_ range: Range<Int>) -> Double {
            var used = 0.0, total = 0.0
            for i in range {
                let delta = zip(now[i], last[i]).map(-)
                let sum = delta.reduce(0, +)
                guard sum > 0 else { continue }
                total += sum
                used += sum - delta[Int(CPU_STATE_IDLE)]
            }
            return total > 0 ? used / total * 100 : 0
        }
        return (busy(0..<eCount), busy(eCount..<now.count))
    }

    /// Raw tick counters, one row per logical core.
    private static func sample() -> [[Double]]? {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cores)).map { core in
            (0..<states).map { Double(info[core * states + $0]) }
        }
    }
}

enum BatteryStatus {
    static func snapshot(_ sources: [[String: Any]]) -> [String: Any] {
        var level: Double = -1
        var charging = false
        var charged = false
        var timeRemaining = -1
        var timeToFull = -1
        var source = "battery"
        for desc in sources {
            let capacity = int(desc[kIOPSCurrentCapacityKey])
            let maxCapacity = int(desc[kIOPSMaxCapacityKey])
            if let capacity, let maxCapacity, maxCapacity > 0 {
                level = Double(capacity) / Double(maxCapacity) * 100.0
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                charging = (state == kIOPSACPowerValue)
                source = charging ? "ac" : "battery"
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
            "source": source,
        ]
    }

    static func smartExtras(_ props: [String: Any]) -> [String: Any] {
        var extras: [String: Any] = [:]
        if let cycles = int(props["CycleCount"]), cycles >= 0 {
            extras["cycles"] = cycles
        }
        if let max = int(props["AppleRawMaxCapacity"]),
           let design = int(props["DesignCapacity"]), design > 0 {
            extras["health"] = Int((Double(max) / Double(design) * 100).rounded())
        }
        if let adapter = props["AdapterDetails"] as? [String: Any],
           let watts = int(adapter["Watts"]), watts > 0 {
            extras["watts"] = watts
        }
        return extras
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
        var snap = snapshot(sources)
        for (key, value) in smartExtras(smartBatteryProps()) {
            snap[key] = value
        }
        snap["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        return snap
    }

    static func smartBatteryProps() -> [String: Any] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator
        ) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dict
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }
}

enum LowPowerMode {
    static func script(_ enabled: Bool) -> String {
        "do shell script \"pmset -a lowpowermode \(enabled ? "1" : "0")\" with administrator privileges"
    }

    static func set(_ enabled: Bool, dryRun: Bool) -> [String: Any] {
        if dryRun {
            return ["ok": true, "lowPowerMode": enabled]
        }
        let result = Subprocess.run("/usr/bin/osascript", ["-e", script(enabled)])
        guard result.ok else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                "ok": false,
                "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "error": msg.isEmpty ? "Could not change Low Power Mode" : msg,
            ]
        }
        return ["ok": true, "lowPowerMode": enabled]
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
        FanController.shared.beginReload()
    }

    public func didReload() {
        FanController.shared.endReload()
    }

    public func register(in engine: Engine, options: [String: Any]) {
        Permissions.beforeHelperUnregister = { FanController.shared.restoreIfNeeded() }
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let systemObj = JS_NewObject(ctx)

        _ = CPUTicks.shared.usage()
        _ = CoreTicks.shared.usage()

        JS_SetPropertyStr(ctx, systemObj, "cpu",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let cores = CoreTicks.shared.usage()
            return JSBridge.newObject(ctx, [
                "usage": CPUTicks.shared.usage(),
                "efficiency": cores.efficiency,
                "performance": cores.performance,
                "efficiencyCores": Double(CoreTopology.split.efficiency),
                "performanceCores": Double(CoreTopology.split.performance),
            ])
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
                // No Intl in QuickJS, so a plugin printing a clock time has no
                // other way to know which half of the world it is printing for.
                "hour12": DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: loc)?.contains("a") ?? false,
            ])
        }, "locale", 0))

        // macotron.system.timeIn(zone, format?) -> "18:42" ("" if the zone is
        // unknown). QuickJS ships without Intl, so a plugin that wants another
        // zone has no way to do this itself short of spawning /bin/date.
        JS_SetPropertyStr(ctx, systemObj, "timeIn",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1, let name = JSBridge.toString(ctx, argv[0]),
                  let zone = TimeZone(identifier: name) ?? TimeZone(abbreviation: name) else {
                return JSBridge.newString(ctx, "")
            }
            var format = "HH:mm"
            if argc >= 2, !JS_IsUndefined(argv[1]), !JS_IsNull(argv[1]),
               let custom = JSBridge.toString(ctx, argv[1]), !custom.isEmpty {
                format = custom
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = format
            return JSBridge.newString(ctx, formatter.string(from: Date()))
        }, "timeIn", 2))

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
            let wanted = limit
            return JSBridge.promise(ctx, dryRun: [Any]()) {
                let text = Subprocess.run("/bin/ps", ["-Ao", "pid,pcpu,comm", "-r"]).stdout
                var results: [Any] = []
                for line in text.split(separator: "\n").dropFirst() {
                    if results.count >= wanted { break }
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
                return .value(results)
            }
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

        JS_SetPropertyStr(ctx, systemObj, "setLowPowerMode",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "setLowPowerMode requires a boolean")
            }
            let enabled = JSBridge.toBool(ctx, argv[0])
            // osascript raises an authorization prompt and waits for the user.
            return JSBridge.promise(ctx, dryRun: LowPowerMode.set(enabled, dryRun: true)) {
                .value(LowPowerMode.set(enabled, dryRun: false))
            }
        }, "setLowPowerMode", 1))

        JS_SetPropertyStr(ctx, systemObj, "darkMode",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newBool(ctx, DarkMode.isOn())
        }, "darkMode", 0))

        JS_SetPropertyStr(ctx, systemObj, "setDarkMode",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "setDarkMode requires a boolean")
            }
            let on = JSBridge.toBool(ctx, argv[0])
            // The SkyLight path is instant, but the osascript fallback is not.
            return JSBridge.promise(ctx, dryRun: DarkMode.set(on, dryRun: true)) {
                .value(DarkMode.set(on, dryRun: false))
            }
        }, "setDarkMode", 1))

        JS_SetPropertyStr(ctx, systemObj, "appearance",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newString(ctx, DarkMode.appearance())
        }, "appearance", 0))

        JS_SetPropertyStr(ctx, systemObj, "setAppearance",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            guard let argv, argc >= 1,
                  let raw = JSBridge.toString(ctx, argv[0]),
                  let mode = DarkMode.parseAppearance(raw) else {
                return QJS_ThrowTypeError(ctx, "setAppearance requires \"light\", \"dark\", or \"auto\"")
            }
            return JSBridge.promise(ctx, dryRun: DarkMode.setAppearance(mode, dryRun: true)) {
                .value(DarkMode.setAppearance(mode, dryRun: false))
            }
        }, "setAppearance", 1))

        JS_SetPropertyStr(ctx, systemObj, "focus",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            return JSBridge.newObject(ctx, FocusStatus.snapshot())
        }, "focus", 0))

        // Setting a floor is an XPC round trip to a daemon launchd may have to
        // cold start, and the SMC writes inside it take a few hundred ms. On
        // the JS thread that is a beachball, so this one hands back a promise.
        JS_SetPropertyStr(ctx, systemObj, "setFanFloor",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            var percent: Int?
            if let argv, argc >= 1, !JSBridge.isUndefined(argv[0]), !JS_IsNull(argv[0]) {
                percent = Int(JSBridge.toInt32(ctx, argv[0]))
            }
            let requested = percent
            return JSBridge.promise(ctx, dryRun: FanController.shared.setFloor(percent, dryRun: true).js) {
                .value(FanController.shared.setFloor(requested, dryRun: false).js)
            }
        }, "setFanFloor", 1))

        JS_SetPropertyStr(ctx, macotron, "system", systemObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
