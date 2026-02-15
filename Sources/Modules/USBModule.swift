// USBModule.swift — macotron.usb: list USB devices and monitor connections
import CQuickJS
import Foundation
import IOKit
import IOKit.usb
import MacotronEngine

@MainActor
public final class USBModule: NativeModule {
    public let name = "usb"
    public let moduleVersion = 1

    private weak var engine: Engine?
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotronObj = JSBridge.getProperty(ctx, global, "macotron")

        let usbObj = JS_NewObject(ctx)

        // macotron.usb.list() → array of {name, vendorID, productID}
        JS_SetPropertyStr(ctx, usbObj, "list",
                          JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx else { return QJS_Undefined() }
            let devices = USBModule.listUSBDevices()
            return JSBridge.newArray(ctx, devices.map { $0 as Any })
        }, "list", 0))

        JS_SetPropertyStr(ctx, macotronObj, "usb", usbObj)
        JS_FreeValue(ctx, macotronObj)
        JS_FreeValue(ctx, global)

        setupNotifications()
    }

    public func cleanup() {
        teardownNotifications()
        engine = nil
    }

    // MARK: - USB Device Enumeration

    private static func listUSBDevices() -> [[String: Any]] {
        var devices: [[String: Any]] = []

        guard let matching = IOServiceMatching(kIOUSBDeviceClassName) else {
            return devices
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return devices }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { service = IOIteratorNext(iterator) }

            var deviceName = ""
            var vendorID: Int = 0
            var productID: Int = 0

            // Get device name
            let nameKey = "USB Product Name" as CFString
            if let nameRef = IORegistryEntryCreateCFProperty(service, nameKey, kCFAllocatorDefault, 0) {
                deviceName = nameRef.takeRetainedValue() as? String ?? "Unknown"
            }
            if deviceName.isEmpty {
                // Fallback: use IOService name
                var name = [CChar](repeating: 0, count: 256)
                if IORegistryEntryGetName(service, &name) == KERN_SUCCESS {
                    deviceName = String(cString: name)
                }
            }

            // Get Vendor ID
            let vendorKey = "idVendor" as CFString
            if let vendorRef = IORegistryEntryCreateCFProperty(service, vendorKey, kCFAllocatorDefault, 0) {
                vendorID = vendorRef.takeRetainedValue() as? Int ?? 0
            }

            // Get Product ID
            let productKey = "idProduct" as CFString
            if let productRef = IORegistryEntryCreateCFProperty(service, productKey, kCFAllocatorDefault, 0) {
                productID = productRef.takeRetainedValue() as? Int ?? 0
            }

            devices.append([
                "name": deviceName,
                "vendorID": vendorID,
                "productID": productID
            ])

            IOObjectRelease(service)
        }
        IOObjectRelease(iterator)

        return devices
    }

    // MARK: - IOKit Notifications (placeholder setup)

    private func setupNotifications() {
        guard let matching = IOServiceMatching(kIOUSBDeviceClassName) else { return }

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Monitor device connections
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Note: IOServiceAddMatchingNotification consumes a reference to matching,
        // so we need a second copy for the removal notification.
        let matchingCopy = IOServiceMatching(kIOUSBDeviceClassName)!

        IOServiceAddMatchingNotification(
            notificationPort,
            kIOFirstMatchNotification,
            matching,
            { refcon, iterator in
                guard let refcon else { return }
                let module = Unmanaged<USBModule>.fromOpaque(refcon).takeUnretainedValue()
                // Drain the iterator to arm the notification
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                // Emit event
                if let engine = module.engine {
                    engine.eventBus.emit("usb:connected", engine: engine)
                }
            },
            selfPtr,
            &addedIterator
        )
        // Drain initial iterator to arm notification
        var service = IOIteratorNext(addedIterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(addedIterator)
        }

        IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            matchingCopy,
            { refcon, iterator in
                guard let refcon else { return }
                let module = Unmanaged<USBModule>.fromOpaque(refcon).takeUnretainedValue()
                // Drain the iterator to arm the notification
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                // Emit event
                if let engine = module.engine {
                    engine.eventBus.emit("usb:disconnected", engine: engine)
                }
            },
            selfPtr,
            &removedIterator
        )
        // Drain initial iterator to arm notification
        service = IOIteratorNext(removedIterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(removedIterator)
        }
    }

    private func teardownNotifications() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
    }
}
