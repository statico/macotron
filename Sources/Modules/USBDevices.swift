// USBDevices.swift — IOKit USB list + attach/detach
import CQuickJS
import Foundation
import IOKit
import IOKit.usb
import MacotronEngine

enum USBDevices {
    static func list() -> [[String: Any]] {
        var out: [[String: Any]] = []
        for name in ["IOUSBHostDevice", "IOUSBDevice"] {
            var iterator = io_iterator_t()
            guard let matching = IOServiceMatching(name) else { continue }
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard kr == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let info = info(service) { out.append(info) }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }
        var seen = Set<String>()
        return out.filter { row in
            let key = "\(row["vendorID"] ?? 0)-\(row["productID"] ?? 0)-\(row["name"] ?? "")"
            return seen.insert(key).inserted
        }
    }

    static func info(_ service: io_service_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        let name = string(dict, ["USB Product Name", "kUSBProductString", "Product Name", "USB Vendor Name"])
            ?? className(service)
        let vendorID = int(dict["idVendor"]) ?? 0
        let productID = int(dict["idProduct"]) ?? 0
        guard vendorID != 0 || productID != 0 || name != nil else { return nil }
        return [
            "name": name ?? "USB device",
            "vendor": string(dict, ["USB Vendor Name", "kUSBVendorString", "Vendor Name"]) ?? "",
            "vendorID": vendorID,
            "productID": productID,
        ]
    }

    private static func className(_ service: io_service_t) -> String? {
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buf.deallocate() }
        guard IOObjectGetClass(service, buf) == KERN_SUCCESS else { return nil }
        let name = String(cString: buf)
        return name.isEmpty ? nil : name
    }

    private static func string(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }
}

private final class USBWatchState: @unchecked Sendable {
    static let shared = USBWatchState()
    var port: IONotificationPortRef?
    var added = io_iterator_t()
    var removed = io_iterator_t()
}

enum USBWatch {
    static func start(_ engine: Engine) {
        USBWatchState.shared.port = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = USBWatchState.shared.port else { return }
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        add(kIOFirstMatchNotification, iterator: &USBWatchState.shared.added, action: "add", engine: engine)
        add(kIOTerminatedNotification, iterator: &USBWatchState.shared.removed, action: "remove", engine: engine)
    }

    static func stop() {
        let state = USBWatchState.shared
        if state.added != 0 { IOObjectRelease(state.added); state.added = 0 }
        if state.removed != 0 { IOObjectRelease(state.removed); state.removed = 0 }
        if let port = state.port {
            IONotificationPortDestroy(port)
            state.port = nil
        }
    }

    private static func add(
        _ type: String,
        iterator: UnsafeMutablePointer<io_iterator_t>,
        action: String,
        engine: Engine
    ) {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return }
        let boxed = USBCallback(action: action, engine: engine)
        let ref = Unmanaged.passRetained(boxed)
        let kr = IOServiceAddMatchingNotification(
            USBWatchState.shared.port,
            type,
            matching,
            usbMatched,
            UnsafeMutableRawPointer(ref.toOpaque()),
            iterator
        )
        guard kr == KERN_SUCCESS else {
            ref.release()
            return
        }
        drain(iterator.pointee, action: action, engine: engine, emit: false)
    }

    static func drain(_ iterator: io_iterator_t, action: String, engine: Engine, emit: Bool) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if emit, let info = USBDevices.info(service) {
                let name = info["name"] as? String ?? "USB device"
                let vendor = info["vendor"] as? String ?? ""
                let vendorID = info["vendorID"] as? Int ?? 0
                let productID = info["productID"] as? Int ?? 0
                DispatchQueue.main.async {
                    Task { @MainActor in
                        guard let ctx = engine.context else { return }
                        let data = JSBridge.newObject(ctx, [
                            "action": action,
                            "name": name,
                            "vendor": vendor,
                            "vendorID": vendorID,
                            "productID": productID,
                        ])
                        engine.eventBus.emit("usb:changed", engine: engine, data: data)
                        JS_FreeValue(ctx, data)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}

private final class USBCallback {
    let action: String
    weak var engine: Engine?
    init(action: String, engine: Engine) {
        self.action = action
        self.engine = engine
    }
}

private let usbMatched: IOServiceMatchingCallback = { refcon, iterator in
    guard let refcon else { return }
    let boxed = Unmanaged<USBCallback>.fromOpaque(refcon).takeUnretainedValue()
    guard let engine = boxed.engine else { return }
    USBWatch.drain(iterator, action: boxed.action, engine: engine, emit: true)
}
