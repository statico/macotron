import Darwin
@preconcurrency import Foundation
import IOKit
import Security

public enum MacotronHelperService {
    public static let plistName = "io.statico.macotron.helper.plist"
    public static let machServiceName = "io.statico.macotron.helper"

    /// Version and bundle path of the app this process was loaded from. The
    /// daemon lives inside the app bundle, so both sides compute it the same
    /// way: a mismatch means launchd is running a helper from another copy.
    public static var identity: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "\(version) at \(Bundle.main.bundlePath)"
    }

    /// True when the bundle on disk no longer matches this running process --
    /// the app was updated, or rebuilt over itself, since launch. In that state
    /// macOS cannot validate this process against its signature, so the helper
    /// rejects its XPC calls and launchd refuses to register the daemon.
    /// Nothing works again until the app is relaunched.
    public static var appReplacedOnDisk: Bool {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return false }
        return SecCodeCheckValidity(me, [], nil) == errSecCSStaticCodeChanged
    }
}

@objc public protocol MacotronHelperProtocol {
    func setFanFloor(_ percent: Int, reply: @escaping (String?) -> Void)
    func restoreFans(reply: @escaping (String?) -> Void)
    /// Release the fans and exit, so the next call starts the helper the
    /// installed app currently ships.
    func shutdown(reply: @escaping (String?) -> Void)
    /// `MacotronHelperService.identity` as this daemon sees it. Doubles as a
    /// ping: a helper too old to answer this fails the call instead.
    func identify(reply: @escaping (String) -> Void)
}

public enum FanFloor {
    /// Whether the floor should still be held. A fan in manual mode does
    /// exactly what it is told, so a partial floor is also a ceiling and macOS
    /// cannot ramp past it — the floor has to yield before that ceiling starts
    /// to matter. Thermal state is the cheap way to know: it costs nothing,
    /// needs no key names, and above all does not require handing the fan back
    /// to find out.
    ///
    /// Only `.serious` and `.critical` release it. `.fair` is ordinary warm
    /// work, where macOS is very unlikely to want more air than a floor the
    /// user chose deliberately, and releasing there would drop the floor
    /// constantly on a machine that is merely busy.
    ///
    /// A floor at full speed cannot be a ceiling, so it is never released.
    ///
    /// A fan whose maximum reads as zero is unreadable, not slow: forcing it
    /// would write a 0 rpm target and, because `floor >= max` holds for two
    /// zeroes, hold that through `.critical`. Never force a fan we cannot
    /// measure.
    public static func shouldForce(
        thermalState: ProcessInfo.ThermalState, floor: Double, max: Double
    ) -> Bool {
        if max <= 0 { return false }
        if floor >= max { return true }
        return thermalState == .nominal || thermalState == .fair
    }

    public static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "?"
        }
    }

    public static func rpm(percent: Int, min: Double, max: Double) -> Double {
        let lo = Swift.min(min, max)
        let hi = Swift.max(min, max)
        let p = Double(Swift.min(100, Swift.max(0, percent))) / 100
        return lo + (hi - lo) * p
    }
}

public struct FanInfo: Sendable {
    public var index: Int
    public var rpm: Double
    public var min: Double
    public var max: Double

    public init(index: Int, rpm: Double, min: Double, max: Double) {
        self.index = index
        self.rpm = rpm
        self.min = min
        self.max = max
    }
}

public enum SMCError: LocalizedError {
    case unavailable
    case notPrivileged
    case thermalLock
    case keyMissing
    case io(kern_return_t)
    case smc(UInt8)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Fan control is not available on this Mac"
        case .notPrivileged: return "This Mac blocked fan-speed writes (administrator / SMC). Nothing to turn on in Settings."
        case .thermalLock: return "macOS thermal manager held the fans"
        case .keyMissing: return "Fan SMC key missing"
        case .io(let kr): return "SMC I/O error \(kr)"
        case .smc(let code): return "SMC error \(code)"
        }
    }
}

public typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

public struct SMCParamStruct {
    public struct SMCVersion {
        public var major: UInt8 = 0
        public var minor: UInt8 = 0
        public var build: UInt8 = 0
        public var reserved: UInt8 = 0
        public var release: UInt16 = 0

        public init() {}
    }

    public struct SMCPLimitData {
        public var version: UInt16 = 0
        public var length: UInt16 = 0
        public var cpuPLimit: UInt32 = 0
        public var gpuPLimit: UInt32 = 0
        public var memPLimit: UInt32 = 0

        public init() {}
    }

    public struct SMCKeyInfoData {
        public var dataSize: UInt32 = 0
        public var dataType: UInt32 = 0
        public var dataAttributes: UInt8 = 0

        public init() {}
    }

    public var key: UInt32 = 0
    public var vers = SMCVersion()
    public var pLimitData = SMCPLimitData()
    public var keyInfo = SMCKeyInfoData()
    public var padding: UInt16 = 0
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: SMCBytes = SMCConnection.emptyBytes()

    public init() {}
}

public final class SMCConnection: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var connection: io_connect_t = 0

    public init() {}

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func open() throws {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.unavailable }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else { throw SMCError.unavailable }
        connection = conn
        assert(MemoryLayout<SMCParamStruct>.stride == 80)
    }

    public func fourCC(_ name: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in name.utf8.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    public func transact(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        lock.lock()
        defer { lock.unlock() }
        try open()
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
        if kr == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard kr == KERN_SUCCESS else { throw SMCError.io(kr) }
        if output.result == 132 { throw SMCError.keyMissing }
        if output.result == 0x82 { throw SMCError.thermalLock }
        guard output.result == 0 else { throw SMCError.smc(output.result) }
        return output
    }

    public func keyInfo(_ name: String) throws -> (size: UInt32, type: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        var input = SMCParamStruct()
        input.key = fourCC(name)
        input.data8 = 9
        let output = try transact(&input)
        return (output.keyInfo.dataSize, output.keyInfo.dataType)
    }

    public func call(
        _ name: String,
        write: Bool,
        size: UInt32 = 0,
        data: SMCBytes? = nil
    ) throws -> SMCParamStruct {
        lock.lock()
        defer { lock.unlock() }
        let info = try keyInfo(name)
        var input = SMCParamStruct()
        input.key = fourCC(name)
        input.keyInfo.dataSize = write ? (size == 0 ? info.size : size) : info.size
        input.keyInfo.dataType = info.type
        input.data8 = write ? 6 : 5
        if write, let data {
            input.bytes = data
        }
        return try transact(&input)
    }

    public func readUInt8(_ key: String) throws -> UInt8 {
        try call(key, write: false).bytes.0
    }

    public func writeUInt8(_ key: String, _ value: UInt8) throws {
        var output = SMCParamStruct()
        output.bytes.0 = value
        _ = try call(key, write: true, size: 1, data: output.bytes)
    }

    public func readRPM(_ key: String) throws -> Double {
        decodeRPM(try call(key, write: false))
    }

    public func writeRPM(_ key: String, _ rpm: Double) throws {
        var bytes = Self.emptyBytes()
        let info = try keyInfo(key)
        encodeRPM(rpm, type: info.type, into: &bytes)
        _ = try call(key, write: true, size: info.size, data: bytes)
    }

    public func decodeRPM(_ output: SMCParamStruct) -> Double {
        let type = output.keyInfo.dataType
        if type == fourCC("flt ") || output.keyInfo.dataSize == 4 {
            return Double(floatLE(output.bytes))
        }
        if type == fourCC("fpe2") || output.keyInfo.dataSize == 2 {
            return Double((Int(output.bytes.0) << 6) + (Int(output.bytes.1) >> 2))
        }
        return Double(floatLE(output.bytes))
    }

    public func encodeRPM(_ rpm: Double, type: UInt32, into bytes: inout SMCBytes) {
        if type == fourCC("fpe2") {
            let value = Int(rpm.rounded())
            bytes.0 = UInt8(value >> 6)
            bytes.1 = UInt8((value << 2) & 0xff)
            return
        }
        var value = Float(rpm)
        withUnsafeBytes(of: &value) { raw in
            bytes.0 = raw[0]
            bytes.1 = raw[1]
            bytes.2 = raw[2]
            bytes.3 = raw[3]
        }
    }

    public func floatLE(_ bytes: SMCBytes) -> Float {
        var value: Float = 0
        withUnsafeMutableBytes(of: &value) { destination in
            destination[0] = bytes.0
            destination[1] = bytes.1
            destination[2] = bytes.2
            destination[3] = bytes.3
        }
        return value
    }

    fileprivate static func emptyBytes() -> SMCBytes {
        (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }
}
