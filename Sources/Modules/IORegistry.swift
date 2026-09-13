// IORegistry.swift — the IOKit match-iterate-release dance, written once.
import Foundation
import IOKit

enum IORegistry {
    /// Every service matching `name`, each released as soon as `body` returns.
    /// Return false from `body` to stop early. `IOServiceGetMatchingServices`
    /// consumes the matching dictionary, so nothing here releases it.
    static func services(matching name: String, _ body: (io_service_t) -> Bool) {
        var iterator = io_iterator_t()
        guard let matching = IOServiceMatching(name),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let keepGoing = body(service)
            IOObjectRelease(service)
            guard keepGoing else { return }
            service = IOIteratorNext(iterator)
        }
    }

    /// `takeRetainedValue` consumes the +1 the create call handed back, so the
    /// dictionary is released whether or not the cast lands.
    static func properties(_ service: io_service_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS
        else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }
}
