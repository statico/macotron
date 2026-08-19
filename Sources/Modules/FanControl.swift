import Darwin
import Foundation
import IOKit
import os

enum FanFloor {
    static func rpm(percent: Int, min: Double, max: Double) -> Double {
        let lo = Swift.min(min, max)
        let hi = Swift.max(min, max)
        let p = Double(Swift.min(100, Swift.max(0, percent))) / 100
        return lo + (hi - lo) * p
    }
}

struct FanInfo {
    var index: Int
    var rpm: Double
    var min: Double
    var max: Double
}

struct FanSnapshot {
    var available: Bool
    var floor: Int?
    var fans: [FanInfo]
    var error: String?

    var js: [String: Any] {
        var dict: [String: Any] = [
            "available": available,
            "fans": fans.map { [
                "index": $0.index,
                "rpm": $0.rpm,
                "min": $0.min,
                "max": $0.max,
            ] as [String: Any] },
        ]
        if let floor { dict["floor"] = floor }
        if let error { dict["error"] = error }
        return dict
    }
}

final class FanController: @unchecked Sendable {
    static let shared = FanController()

    private let log = Logger(subsystem: "com.macotron", category: "fan")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macotron.fan")
    private var connection: io_connect_t = 0
    private var floor: Int?
    private var lastError: String?
    private var didUnlock = false
    private var timer: DispatchSourceTimer?
    private var modeKey = "F0Md"

    func snapshot() -> FanSnapshot {
        lock.lock()
        defer { lock.unlock() }
        do {
            try open()
            let fans = try readFans()
            return FanSnapshot(available: !fans.isEmpty, floor: floor, fans: fans, error: lastError)
        } catch {
            return FanSnapshot(available: false, floor: floor, fans: [], error: error.localizedDescription)
        }
    }

    func setFloor(_ percent: Int?, dryRun: Bool) -> FanSnapshot {
        lock.lock()
        floor = percent.flatMap { $0 > 0 ? min(100, $0) : nil }
        lastError = nil
        lock.unlock()
        if dryRun {
            return snapshot()
        }
        queue.async { [weak self] in
            self?.apply()
        }
        startTimer(percent != nil && (percent ?? 0) > 0)
        return snapshot()
    }

    func restore() {
        lock.lock()
        floor = nil
        lastError = nil
        lock.unlock()
        startTimer(false)
        queue.sync { apply() }
    }

    private func startTimer(_ on: Bool) {
        lock.lock()
        timer?.cancel()
        timer = nil
        guard on else {
            lock.unlock()
            return
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.apply() }
        t.resume()
        timer = t
        lock.unlock()
    }

    private func apply() {
        lock.lock()
        let target = floor
        lock.unlock()
        do {
            try open()
            try probeModeKey()
            let fans = try readFans()
            guard !fans.isEmpty else {
                lock.lock(); lastError = "This Mac has no fans"; lock.unlock()
                return
            }
            if let percent = target {
                try applyFloor(percent, fans: fans)
            } else {
                try restoreAuto(count: fans.count)
            }
            lock.lock(); lastError = nil; lock.unlock()
        } catch {
            lock.lock(); lastError = error.localizedDescription; lock.unlock()
            log.error("fan apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyFloor(_ percent: Int, fans: [FanInfo]) throws {
        for fan in fans {
            let floorRpm = FanFloor.rpm(percent: percent, min: fan.min, max: fan.max)
            if percent >= 100 || fan.rpm + 80 < floorRpm {
                try unlock(fan.index)
                try writeRPM(key(fan.index, "Tg"), floorRpm)
            } else {
                try writeMode(fan.index, 0)
            }
        }
    }

    private func restoreAuto(count: Int) throws {
        for i in 0..<count {
            try writeMode(i, 0)
        }
        if didUnlock {
            _ = try? writeUInt8("Ftst", 0)
            didUnlock = false
        }
    }

    private func unlock(_ index: Int) throws {
        if (try? readUInt8(modeKeyFor(index))) == 1 { return }
            if (try? writeMode(index, 1)) != nil, (try? readUInt8(modeKeyFor(index))) == 1 {
                return
            }
        _ = try? writeUInt8("Ftst", 1)
        didUnlock = true
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.1)
            if (try? writeMode(index, 1)) != nil, (try? readUInt8(modeKeyFor(index))) == 1 {
                return
            }
        }
        throw FanError.thermalLock
    }

    private func probeModeKey() throws {
        if (try? readUInt8("F0Md")) != nil {
            modeKey = "F0Md"
            return
        }
        if (try? readUInt8("F0md")) != nil {
            modeKey = "F0md"
        }
    }

    private func modeKeyFor(_ index: Int) -> String {
        let suffix = String(modeKey.dropFirst(2))
        return "F\(index)\(suffix)"
    }

    private func key(_ index: Int, _ suffix: String) -> String {
        "F\(index)\(suffix)"
    }

    private func readFans() throws -> [FanInfo] {
        let n = Int(try readUInt8("FNum"))
        var fans: [FanInfo] = []
        for i in 0..<n {
            fans.append(FanInfo(
                index: i,
                rpm: (try? readRPM(key(i, "Ac"))) ?? 0,
                min: (try? readRPM(key(i, "Mn"))) ?? 0,
                max: (try? readRPM(key(i, "Mx"))) ?? 0
            ))
        }
        return fans
    }

    private func writeMode(_ index: Int, _ value: UInt8) throws {
        try writeUInt8(modeKeyFor(index), value)
    }

    private func open() throws {
        if connection != 0 { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw FanError.unavailable }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw FanError.unavailable }
        connection = conn
        assert(MemoryLayout<SMCParamStruct>.stride == 80)
    }

    private func readUInt8(_ key: String) throws -> UInt8 {
        try call(key, write: false).bytes.0
    }

    private func writeUInt8(_ key: String, _ value: UInt8) throws {
        var output = SMCParamStruct()
        output.bytes.0 = value
        _ = try call(key, write: true, size: 1, data: output.bytes)
    }

    private func readRPM(_ key: String) throws -> Double {
        let out = try call(key, write: false)
        return decodeRPM(out)
    }

    private func writeRPM(_ key: String, _ rpm: Double) throws {
        var bytes = emptyBytes()
        let info = try keyInfo(key)
        encodeRPM(rpm, type: info.type, into: &bytes)
        _ = try call(key, write: true, size: info.size, data: bytes)
    }

    private func decodeRPM(_ out: SMCParamStruct) -> Double {
        let type = out.keyInfo.dataType
        if type == fourCC("flt ") || out.keyInfo.dataSize == 4 {
            return Double(floatLE(out.bytes))
        }
        if type == fourCC("fpe2") || out.keyInfo.dataSize == 2 {
            return Double((Int(out.bytes.0) << 6) + (Int(out.bytes.1) >> 2))
        }
        return Double(floatLE(out.bytes))
    }

    private func encodeRPM(_ rpm: Double, type: UInt32, into bytes: inout SMCBytes) {
        if type == fourCC("fpe2") {
            let n = Int(rpm.rounded())
            bytes.0 = UInt8(n >> 6)
            bytes.1 = UInt8((n << 2) & 0xff)
            return
        }
        var value = Float(rpm)
        withUnsafeBytes(of: &value) { raw in
            bytes.0 = raw[0]; bytes.1 = raw[1]; bytes.2 = raw[2]; bytes.3 = raw[3]
        }
    }

    private func floatLE(_ bytes: SMCBytes) -> Float {
        var value: Float = 0
        withUnsafeMutableBytes(of: &value) { dest in
            dest[0] = bytes.0; dest[1] = bytes.1; dest[2] = bytes.2; dest[3] = bytes.3
        }
        return value
    }

    private struct KeyMeta { var size: UInt32; var type: UInt32 }

    private func keyInfo(_ name: String) throws -> KeyMeta {
        var input = SMCParamStruct()
        input.key = fourCC(name)
        input.data8 = 9
        let out = try transact(&input)
        return KeyMeta(size: out.keyInfo.dataSize, type: out.keyInfo.dataType)
    }

    private func call(_ name: String, write: Bool, size: UInt32 = 0, data: SMCBytes? = nil) throws -> SMCParamStruct {
        let info = try keyInfo(name)
        var input = SMCParamStruct()
        input.key = fourCC(name)
        input.keyInfo.dataSize = write ? (size == 0 ? info.size : size) : info.size
        input.keyInfo.dataType = info.type
        input.data8 = write ? 6 : 5
        if write, let data { input.bytes = data }
        return try transact(&input)
    }

    private func transact(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )
        if kr == kIOReturnNotPrivileged { throw FanError.notPrivileged }
        guard kr == KERN_SUCCESS else { throw FanError.io(kr) }
        if output.result == 132 { throw FanError.keyMissing }
        if output.result == 0x82 { throw FanError.thermalLock }
        guard output.result == 0 else { throw FanError.smc(output.result) }
        return output
    }
}

private enum FanError: LocalizedError {
    case unavailable
    case notPrivileged
    case thermalLock
    case keyMissing
    case io(kern_return_t)
    case smc(UInt8)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Fan control is not available on this Mac"
        case .notPrivileged: return "Fan speed writes need administrator access"
        case .thermalLock: return "macOS thermal manager held the fans"
        case .keyMissing: return "Fan SMC key missing"
        case .io(let kr): return "SMC I/O error \(kr)"
        case .smc(let code): return "SMC error \(code)"
        }
    }
}

private func fourCC(_ name: String) -> UInt32 {
    var v: UInt32 = 0
    for b in name.utf8.prefix(4) { v = (v << 8) | UInt32(b) }
    return v
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private func emptyBytes() -> SMCBytes {
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private struct SMCParamStruct {
    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = emptyBytes()
}
