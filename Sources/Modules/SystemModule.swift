// SystemModule.swift — macotron.system: CPU temp, memory, battery info
import CQuickJS
import Foundation
import MacotronEngine
import IOKit.ps
import os

private let logger = Logger(subsystem: "com.macotron", category: "system")

@MainActor
public final class SystemModule: NativeModule {
    public let name = "system"

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let systemObj = JS_NewObject(ctx)

        // macotron.system.cpuTemp() -> number
        JS_SetPropertyStr(ctx, systemObj, "cpuTemp",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            // SMC reading requires a kernel connection; return 0 as placeholder
            // A full implementation would use IOServiceOpen to read "TC0P" from AppleSMC
            return JSBridge.newFloat64(ctx, 0.0)
        }, "cpuTemp", 0))

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

        // macotron.system.battery() -> {level, charging}
        JS_SetPropertyStr(ctx, systemObj, "battery",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }

            var level: Double = -1
            var isCharging = false

            if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any] {
                for source in sources {
                    if let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
                        .takeUnretainedValue() as? [String: Any] {
                        if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
                           let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int,
                           maxCapacity > 0 {
                            level = Double(capacity) / Double(maxCapacity) * 100.0
                        }
                        if let state = desc[kIOPSPowerSourceStateKey] as? String {
                            isCharging = (state == kIOPSACPowerValue)
                        }
                    }
                }
            }

            return JSBridge.newObject(ctx, [
                "level": level,
                "charging": isCharging
            ])
        }, "battery", 0))

        JS_SetPropertyStr(ctx, macotron, "system", systemObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }
}
