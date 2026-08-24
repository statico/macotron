@preconcurrency import Foundation
import os
import ServiceManagement
import SMCKit

private let logger = Logger(subsystem: "io.statico.macotron", category: "helper")

struct FanSnapshot: Sendable {
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

public final class FanController: @unchecked Sendable {
    public static let shared = FanController()

    private let lock = NSLock()
    private let smc = SMCConnection()
    private var floor: Int?
    private var helperConnection: NSXPCConnection?
    private var recycled = false

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
            result.error = "Macotron helper is not installed"
            return result
        }
        lock.unlock()

        let error: String?
        if let requestedFloor {
            error = call { $0.setFanFloor(requestedFloor, reply: $1) }
        } else {
            error = call { $0.restoreFans(reply: $1) }
        }

        // Let go of the daemon once nothing is held, so it can exit and the
        // next call starts whatever helper the current app ships.
        if requestedFloor == nil, error == nil {
            dropConnection()
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
        _ = call { $0.restoreFans(reply: $1) }
        dropConnection()
    }

    private var helperEnabled: Bool {
        SMAppService.daemon(plistName: MacotronHelperService.plistName).status == .enabled
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

    /// Startup check for an installed helper: can launchd start it, does it
    /// answer, and did it come from this copy of the app? Connecting is the
    /// only way to know -- `SMAppService.status` reports the registration, not
    /// the daemon. A matching helper needs no recycling on first use; anything
    /// else is told to quit so the next call starts the one this app ships.
    public func checkHelper() {
        guard helperEnabled else { return }
        // Shutting the helper down would fail the same validation the calls do,
        // and the helper this app ships cannot start until the app restarts.
        guard !MacotronHelperService.appReplacedOnDisk else {
            logger.error("helper check: app replaced on disk since launch; relaunch to use the helper")
            return
        }
        let reply = HelperReply()
        let proxy = connection().remoteObjectProxyWithErrorHandler { error in
            reply.finish(Self.displayError(error.localizedDescription))
        }
        guard let helper = proxy as? MacotronHelperProtocol else {
            logger.error("helper check: connection failed")
            return
        }
        helper.identify { reply.finish(nil, value: $0) }
        let error = reply.wait()
        let running = reply.value
        dropConnection()

        if error == nil, running == MacotronHelperService.identity {
            logger.info("helper check: running \(running ?? "", privacy: .public)")
            lock.lock()
            recycled = true
            lock.unlock()
            return
        }
        if let error {
            // Installed but unreachable: a stale registration, a helper too old
            // to answer, or one that will not start.
            logger.error("helper check: \(error, privacy: .public)")
        } else {
            logger.error("""
                helper check: running \(running ?? "", privacy: .public), \
                app is \(MacotronHelperService.identity, privacy: .public)
                """)
        }
        _ = call({ $0.shutdown(reply: $1) }, recycling: true)
        dropConnection()
    }

    /// The daemon launchd has running was started from whatever app was
    /// installed at the time, and it never re-execs. Ask the one from the
    /// last app to quit the first time this app needs it, so the call after
    /// it starts the helper this app ships.
    private func recycleHelper() {
        lock.lock()
        let done = recycled
        recycled = true
        lock.unlock()
        guard !done else { return }
        _ = call({ $0.shutdown(reply: $1) }, recycling: true)
        dropConnection()
    }

    private func call(
        _ body: (MacotronHelperProtocol, @escaping (String?) -> Void) -> Void,
        recycling: Bool = false
    ) -> String? {
        if !recycling { recycleHelper() }
        let reply = HelperReply()
        let proxy = connection().remoteObjectProxyWithErrorHandler { error in
            reply.finish(Self.displayError(error.localizedDescription))
        }
        guard let helper = proxy as? MacotronHelperProtocol else {
            return "Macotron helper connection failed"
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
            machServiceName: MacotronHelperService.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: MacotronHelperProtocol.self)
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
        helperUnreachable(error) ? "Macotron helper is not installed" : error
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
    private var payload: String?

    func finish(_ error: String?, value: String? = nil) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        self.error = error
        payload = value
        lock.unlock()
        semaphore.signal()
    }

    /// Whatever the reply carried, once `wait()` has returned.
    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return payload
    }

    func wait() -> String? {
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            return "Macotron helper did not respond"
        }
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
