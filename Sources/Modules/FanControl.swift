@preconcurrency import Foundation
import ServiceManagement
import SMCKit

struct FanSnapshot {
    var available: Bool
    var controllable: Bool
    var floor: Int?
    var fans: [FanInfo]
    var error: String?

    var js: [String: Any] {
        var dictionary: [String: Any] = [
            "available": available,
            "controllable": controllable,
            "fans": fans.map {
                [
                    "index": $0.index,
                    "rpm": $0.rpm,
                    "min": $0.min,
                    "max": $0.max,
                ] as [String: Any]
            },
        ]
        if let floor {
            dictionary["floor"] = floor
        }
        if let error {
            dictionary["error"] = error
        }
        return dictionary
    }
}

final class FanController: @unchecked Sendable {
    static let shared = FanController()

    private let lock = NSLock()
    private let smc = SMCConnection()
    private var floor: Int?
    private var helperConnection: NSXPCConnection?

    func snapshot() -> FanSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    func setFloor(_ percent: Int?, dryRun: Bool) -> FanSnapshot {
        let requestedFloor = percent.flatMap { $0 > 0 ? min(100, $0) : nil }
        lock.lock()
        if dryRun || (requestedFloor == nil && floor == nil) {
            let result = snapshotLocked()
            lock.unlock()
            return result
        }
        guard helperEnabled else {
            var result = snapshotLocked()
            lock.unlock()
            result.error = "Fan helper is not installed"
            return result
        }
        lock.unlock()

        let error: String?
        if let requestedFloor {
            error = call { $0.setFloor(requestedFloor, reply: $1) }
        } else {
            error = call { $0.restore(reply: $1) }
        }

        lock.lock()
        if error == nil {
            floor = requestedFloor
        }
        var result = snapshotLocked()
        lock.unlock()
        if let error {
            result.error = Self.displayError(error)
            if Self.helperUnreachable(error) {
                result.controllable = false
            }
        }
        return result
    }

    func restoreIfNeeded() {
        lock.lock()
        let needed = floor != nil && helperEnabled
        floor = nil
        lock.unlock()
        guard needed else { return }
        _ = call { $0.restore(reply: $1) }
        dropConnection()
    }

    private var helperEnabled: Bool {
        SMAppService.daemon(plistName: FanHelperService.plistName).status == .enabled
    }

    private func snapshotLocked() -> FanSnapshot {
        do {
            let fans = try readFans()
            return FanSnapshot(
                available: !fans.isEmpty,
                controllable: helperEnabled && !fans.isEmpty,
                floor: floor,
                fans: fans,
                error: nil
            )
        } catch {
            return FanSnapshot(
                available: false,
                controllable: false,
                floor: floor,
                fans: [],
                error: error.localizedDescription
            )
        }
    }

    private func readFans() throws -> [FanInfo] {
        let count = Int(try smc.readUInt8("FNum"))
        return (0..<count).map { index in
            FanInfo(
                index: index,
                rpm: (try? smc.readRPM(key(index, "Ac"))) ?? 0,
                min: (try? smc.readRPM(key(index, "Mn"))) ?? 0,
                max: (try? smc.readRPM(key(index, "Mx"))) ?? 0
            )
        }
    }

    private func call(_ body: (FanHelperProtocol, @escaping (String?) -> Void) -> Void) -> String? {
        let reply = HelperReply()
        let proxy = connection().remoteObjectProxyWithErrorHandler { error in
            reply.finish(Self.displayError(error.localizedDescription))
        }
        guard let helper = proxy as? FanHelperProtocol else {
            return "Fan helper connection failed"
        }
        body(helper) { error in
            reply.finish(error)
        }
        return reply.wait()
    }

    private func connection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let helperConnection { return helperConnection }
        let connection = NSXPCConnection(
            machServiceName: FanHelperService.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            lock.lock()
            if helperConnection === connection {
                helperConnection = nil
            }
            lock.unlock()
        }
        connection.resume()
        helperConnection = connection
        return connection
    }

    private func dropConnection() {
        lock.lock()
        let connection = helperConnection
        helperConnection = nil
        lock.unlock()
        connection?.invalidationHandler = nil
        connection?.invalidate()
    }

    private func key(_ index: Int, _ suffix: String) -> String {
        "F\(index)\(suffix)"
    }

    /// XPC's own copy is a long "Couldn't communicate with a helper application".
    /// That just means the daemon is not running or rejected us.
    static func displayError(_ error: String) -> String {
        helperUnreachable(error) ? "Fan helper is not installed" : error
    }

    static func helperUnreachable(_ error: String) -> Bool {
        let text = error.lowercased()
        return text.contains("couldn't communicate")
            || text.contains("couldn’t communicate")
            || text.contains("helper application")
            || text.contains("connection invalid")
            || text.contains("connection interrupted")
            || text.contains("connection failed")
            || text.contains("did not respond")
    }
}

private final class HelperReply: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var completed = false
    private var error: String?

    func finish(_ error: String?) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        self.error = error
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> String? {
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            return "Fan helper did not respond"
        }
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
