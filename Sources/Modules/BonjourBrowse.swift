import Foundation

enum BonjourBrowse {
    static func normalizeType(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix(".") { t.removeLast() }
        if t.lowercased().hasSuffix(".local") {
            t.removeLast(6)
            while t.hasSuffix(".") { t.removeLast() }
        }
        return t
    }

    static func txtStrings(_ txt: [String: Data]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: txt.map { key, data in
            (key, String(data: data, encoding: .utf8) ?? data.base64EncodedString())
        })
    }

    static func row(name: String, type: String, host: String, port: Int, txt: [String: Data]) -> [String: Any] {
        [
            "name": name,
            "type": normalizeType(type),
            "host": host,
            "port": port,
            "txt": txtStrings(txt) as [String: Any],
        ]
    }

    static func browse(type: String, timeout: TimeInterval = 1.5, dryRun: Bool) -> [[String: Any]] {
        browse(types: [type], timeout: timeout, dryRun: dryRun)
    }

    static func browse(types: [String], timeout: TimeInterval, dryRun: Bool) -> [[String: Any]] {
        if dryRun { return [] }
        let collector = BonjourCollector()
        collector.search(types: types.map(normalizeType), timeout: max(0.05, timeout))
        return collector.rows
    }
}

private final class BonjourCollector: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private(set) var rows: [[String: Any]] = []

    /// Blocks its thread for the whole timeout, so callers must be off the main
    /// one. NetServiceBrowser reports through the run loop of the thread that
    /// started the search, which is why this spins one rather than sleeping:
    /// a sleeping thread would collect nothing.
    func search(types: [String], timeout: TimeInterval) {
        for type in types {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 1)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, !host.isEmpty, sender.port > 0 else { return }
        let txt = sender.txtRecordData().map { NetService.dictionary(fromTXTRecord: $0) } ?? [:]
        rows.append(BonjourBrowse.row(name: sender.name, type: sender.type, host: host, port: sender.port, txt: txt))
    }
}
