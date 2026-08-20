import CQuickJS
import Foundation
import IOKit
import IOKit.hid
import MacotronEngine

struct HIDFilter: Equatable {
    var vendorID: Int?
    var productID: Int?
    var usagePage: Int?
    var usage: Int?
    var serial: String?
    var path: String?

    init(
        vendorID: Int? = nil,
        productID: Int? = nil,
        usagePage: Int? = nil,
        usage: Int? = nil,
        serial: String? = nil,
        path: String? = nil
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.usage = usage
        self.serial = serial
        self.path = path
    }

    init(_ dict: [String: Any]) {
        if let raw = dict["vidpid"] as? String {
            let pair = HIDFilter.parseVidPid(raw)
            vendorID = pair.vendorID
            productID = pair.productID
        }
        if let n = HIDFilter.int(dict["vendorID"]) { vendorID = n }
        if let n = HIDFilter.int(dict["productID"]) { productID = n }
        if let n = HIDFilter.int(dict["usagePage"]) { usagePage = n }
        if let n = HIDFilter.int(dict["usage"]) { usage = n }
        if let s = dict["serial"] as? String, !s.isEmpty { serial = s }
        if let s = dict["path"] as? String, !s.isEmpty { path = s }
    }

    func matches(_ row: [String: Any]) -> Bool {
        if let vendorID, HIDFilter.int(row["vendorID"]) != vendorID { return false }
        if let productID, HIDFilter.int(row["productID"]) != productID { return false }
        if let usagePage, HIDFilter.int(row["usagePage"]) != usagePage { return false }
        if let usage, HIDFilter.int(row["usage"]) != usage { return false }
        if let serial, (row["serial"] as? String) != serial { return false }
        if let path, (row["path"] as? String) != path { return false }
        return true
    }

    static func parseVidPid(_ raw: String) -> (vendorID: Int?, productID: Int?) {
        let parts = raw.split { $0 == "/" || $0 == ":" }.map(String.init)
        if parts.count == 1 { return (parseHex(parts[0]), nil) }
        if parts.count >= 2 { return (parseHex(parts[0]), parseHex(parts[1])) }
        return (nil, nil)
    }

    static func parseHex(_ raw: String) -> Int? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("0x") { t.removeFirst(2) }
        guard !t.isEmpty, let n = Int(t, radix: 16), n != 0 else { return nil }
        return n
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        default: return nil
        }
    }
}

enum HIDBytes {
    static func parse(_ value: Any) -> [UInt8]? {
        if let arr = value as? [Any] {
            var out: [UInt8] = []
            out.reserveCapacity(arr.count)
            for item in arr {
                guard let b = byte(item) else { return nil }
                out.append(b)
            }
            return out
        }
        if let s = value as? String {
            return parseList(s)
        }
        return nil
    }

    static func parseList(_ raw: String) -> [UInt8]? {
        let parts = raw.split { $0 == "," || $0 == " " || $0 == ":" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out: [UInt8] = []
        for part in parts {
            guard let b = byte(part) else { return nil }
            out.append(b)
        }
        return out
    }

    static func pad(_ bytes: [UInt8], length: Int?) -> [UInt8] {
        guard let length, length > bytes.count else { return bytes }
        return bytes + [UInt8](repeating: 0, count: length - bytes.count)
    }

    static func byte(_ value: Any) -> UInt8? {
        if let i = value as? Int, (0...255).contains(i) { return UInt8(i) }
        if let n = value as? NSNumber {
            let i = n.intValue
            return (0...255).contains(i) ? UInt8(i) : nil
        }
        if let d = value as? Double {
            let i = Int(d)
            return (0...255).contains(i) ? UInt8(i) : nil
        }
        if let s = value as? String {
            var t = s.trimmingCharacters(in: .whitespaces).lowercased()
            let hex = t.hasPrefix("0x") || t.contains(where: { $0.isHexDigit && $0.isLetter })
            if t.hasPrefix("0x") { t.removeFirst(2) }
            guard let n = Int(t, radix: hex ? 16 : 10), (0...255).contains(n) else { return nil }
            return UInt8(n)
        }
        return nil
    }
}

enum HIDReport {
    /// First byte is the report id, same as hidapi / hidapitester.
    /// A leading 0 is not sent; a non-zero id stays in the buffer.
    static func setSlice(_ bytes: [UInt8]) -> (reportID: CFIndex, start: Int) {
        let reportID = CFIndex(bytes.first ?? 0)
        if reportID == 0, bytes.count > 1 { return (0, 1) }
        return (reportID, 0)
    }
}

enum HIDDevices {
    static func list(_ filter: HIDFilter = HIDFilter()) -> [[String: Any]] {
        guard let devices = copyDevices() else { return [] }
        return devices.compactMap(info).filter(filter.matches)
    }

    static func first(_ filter: HIDFilter) -> IOHIDDevice? {
        guard let devices = copyDevices() else { return nil }
        return devices.first { filter.matches(info($0)) }
    }

    static func info(_ device: IOHIDDevice) -> [String: Any] {
        let vendorID = int(device, kIOHIDVendorIDKey) ?? 0
        let productID = int(device, kIOHIDProductIDKey) ?? 0
        return [
            "name": string(device, kIOHIDProductKey) ?? "HID device",
            "vendor": string(device, kIOHIDManufacturerKey) ?? "",
            "vendorID": vendorID,
            "productID": productID,
            "usagePage": int(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            "usage": int(device, kIOHIDPrimaryUsageKey) ?? 0,
            "serial": string(device, kIOHIDSerialNumberKey) ?? "",
            "path": path(device),
            "maxInput": int(device, kIOHIDMaxInputReportSizeKey) ?? 64,
            "maxOutput": int(device, kIOHIDMaxOutputReportSizeKey) ?? 64,
            "maxFeature": int(device, kIOHIDMaxFeatureReportSizeKey) ?? 64,
        ]
    }

    static func maxReport(_ device: IOHIDDevice, _ type: IOHIDReportType) -> Int {
        let key: String
        switch type {
        case kIOHIDReportTypeOutput: key = kIOHIDMaxOutputReportSizeKey
        case kIOHIDReportTypeFeature: key = kIOHIDMaxFeatureReportSizeKey
        default: key = kIOHIDMaxInputReportSizeKey
        }
        return max(int(device, key) ?? 64, 1)
    }

    static func setReport(_ device: IOHIDDevice, type: IOHIDReportType, bytes: [UInt8]) -> (ok: Bool, written: Int, error: String?) {
        guard !bytes.isEmpty else { return (false, 0, "empty report") }
        let slice = HIDReport.setSlice(bytes)
        let written = bytes.count - slice.start
        let kr = bytes.withUnsafeBufferPointer { buf -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                type,
                slice.reportID,
                buf.baseAddress! + slice.start,
                written
            )
        }
        if kr == kIOReturnSuccess { return (true, written, nil) }
        return (false, 0, hidError(kr))
    }

    static func getReport(_ device: IOHIDDevice, type: IOHIDReportType, reportID: Int, length: Int) -> [UInt8]? {
        let size = max(length, 1)
        var buf = [UInt8](repeating: 0, count: size)
        buf[0] = UInt8(clamping: reportID)
        var count = CFIndex(size)
        let kr: IOReturn
        if reportID == 0, size > 1 {
            count = CFIndex(size - 1)
            kr = buf.withUnsafeMutableBufferPointer { ptr in
                IOHIDDeviceGetReport(device, type, 0, ptr.baseAddress! + 1, &count)
            }
            count += 1
        } else {
            kr = buf.withUnsafeMutableBufferPointer { ptr in
                IOHIDDeviceGetReport(device, type, CFIndex(reportID), ptr.baseAddress!, &count)
            }
        }
        guard kr == kIOReturnSuccess else { return nil }
        return Array(buf.prefix(max(Int(count), 1)))
    }

    static func reportDescriptor(_ device: IOHIDDevice) -> [Int]? {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) else {
            return nil
        }
        if let data = value as? Data {
            return data.map { Int($0) }
        }
        if let data = value as? NSData {
            return (0..<data.length).map { Int(data.bytes.load(fromByteOffset: $0, as: UInt8.self)) }
        }
        return nil
    }

    private static func copyDevices() -> [IOHIDDevice]? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        return (set as NSSet).allObjects.map { $0 as! IOHIDDevice }
    }

    private static func path(_ device: IOHIDDevice) -> String {
        let service = IOHIDDeviceGetService(device)
        if service != 0 {
            var buf = [CChar](repeating: 0, count: 512)
            if IORegistryEntryGetPath(service, kIOServicePlane, &buf) == KERN_SUCCESS,
               let path = String(validating: buf.prefix { $0 != 0 }, as: UTF8.self) {
                return path
            }
        }
        let location = int(device, kIOHIDLocationIDKey) ?? 0
        let usagePage = int(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = int(device, kIOHIDPrimaryUsageKey) ?? 0
        return String(format: "%08x-%04x-%04x", location, usagePage, usage)
    }

    private static func int(_ device: IOHIDDevice, _ key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return HIDFilter.int(value)
    }

    private static func string(_ device: IOHIDDevice, _ key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    static func hidError(_ kr: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: kr))
    }
}

final class HIDOpenDevice: @unchecked Sendable {
    let id: String
    let device: IOHIDDevice
    weak var engine: Engine?
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var bufferLen = 0

    init(id: String, device: IOHIDDevice, engine: Engine?) {
        self.id = id
        self.device = device
        self.engine = engine
    }

    deinit {
        stopListen()
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func listen() -> (ok: Bool, error: String?) {
        let size = HIDDevices.maxReport(device, kIOHIDReportTypeInput)
        if buffer == nil {
            buffer = .allocate(capacity: size)
            bufferLen = size
        }
        guard let buffer else { return (false, "no buffer") }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            bufferLen,
            hidInputReport,
            Unmanaged.passUnretained(self).toOpaque()
        )
        return (true, nil)
    }

    func stopListen() {
        if let buffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 0, nil, nil)
        }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        buffer?.deallocate()
        buffer = nil
        bufferLen = 0
    }

    func emit(reportId: UInt32, data: [UInt8]) {
        MainActor.assumeIsolated {
            guard let engine, let ctx = engine.context else { return }
            let payload = JSBridge.newObject(ctx, [
                "id": id,
                "reportId": Int(reportId),
                "data": data.map { Int($0) },
            ])
            engine.eventBus.emit("hid:input", engine: engine, data: payload)
            JS_FreeValue(ctx, payload)
        }
    }
}

private let hidInputReport: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
    guard result == kIOReturnSuccess, let context, length > 0 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
    let reportId = reportID
    let device = Unmanaged<HIDOpenDevice>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        device.emit(reportId: reportId, data: bytes)
    }
}

@MainActor
final class HIDHub {
    private var nextID = 1
    private var open: [String: HIDOpenDevice] = [:]
    weak var engine: Engine?

    func open(_ filter: HIDFilter) -> [String: Any]? {
        guard let device = HIDDevices.first(filter) else { return nil }
        let kr = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard kr == kIOReturnSuccess else { return nil }
        let id = String(nextID)
        nextID += 1
        open[id] = HIDOpenDevice(id: id, device: device, engine: engine)
        var row = HIDDevices.info(device)
        row["id"] = id
        return row
    }

    func close(_ id: String) {
        open.removeValue(forKey: id)
    }

    func closeAll() {
        open.removeAll()
    }

    func device(_ id: String) -> IOHIDDevice? {
        open[id]?.device
    }

    func listen(_ id: String) -> [String: Any] {
        guard let session = open[id] else { return ["ok": false, "error": "not open"] }
        let result = session.listen()
        if result.ok { return ["ok": true] }
        return ["ok": false, "error": result.error ?? "listen failed"]
    }

    func unlisten(_ id: String) {
        open[id]?.stopListen()
    }
}
