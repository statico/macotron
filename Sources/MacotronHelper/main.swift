import Darwin
import Foundation
import Security
import SMCKit
import os

final class HelperService: NSObject, MacotronHelperProtocol, @unchecked Sendable {
    private let log = Logger(subsystem: "io.statico.macotron", category: "helper")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macotron.helper.fan")
    private let smc = SMCConnection()
    private var didUnlock = false
    private var floor: Int?
    private var modeKey = "F0Md"
    private var timer: DispatchSourceTimer?

    func setFanFloor(_ percent: Int, reply: @escaping (String?) -> Void) {
        lock.lock()
        floor = min(100, max(1, percent))
        let error = apply()
        startTimer(error == nil)
        lock.unlock()
        reply(error)
    }

    func restoreFans(reply: @escaping (String?) -> Void) {
        lock.lock()
        floor = nil
        startTimer(false)
        let error = apply()
        lock.unlock()
        reply(error)
    }

    func restoreForFailsafe() {
        lock.lock()
        defer { lock.unlock() }
        floor = nil
        startTimer(false)
        if let error = apply() {
            log.error("failsafe restore failed: \(error, privacy: .public)")
        }
    }

    private func startTimer(_ enabled: Bool) {
        timer?.cancel()
        timer = nil
        guard enabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock()
            _ = apply()
            lock.unlock()
        }
        timer.resume()
        self.timer = timer
    }

    private func apply() -> String? {
        do {
            try probeModeKey()
            let fans = try readFans()
            guard !fans.isEmpty else {
                return "This Mac has no fans"
            }
            if let floor {
                try applyFloor(floor, fans: fans)
            } else {
                try restoreAuto(count: fans.count)
            }
            return nil
        } catch {
            log.error("fan apply failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func applyFloor(_ percent: Int, fans: [FanInfo]) throws {
        for fan in fans {
            let floorRPM = FanFloor.rpm(percent: percent, min: fan.min, max: fan.max)
            if percent >= 100 || fan.rpm + 80 < floorRPM {
                try unlock(fan.index)
                try smc.writeRPM(key(fan.index, "Tg"), floorRPM)
            } else {
                try writeMode(fan.index, 0)
            }
        }
    }

    private func restoreAuto(count: Int) throws {
        for index in 0..<count {
            try writeMode(index, 0)
        }
        if didUnlock {
            _ = try? smc.writeUInt8("Ftst", 0)
            didUnlock = false
        }
    }

    private func unlock(_ index: Int) throws {
        if (try? smc.readUInt8(modeKeyFor(index))) == 1 { return }
        if (try? writeMode(index, 1)) != nil,
           (try? smc.readUInt8(modeKeyFor(index))) == 1 {
            return
        }
        _ = try? smc.writeUInt8("Ftst", 1)
        didUnlock = true
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.1)
            if (try? writeMode(index, 1)) != nil,
               (try? smc.readUInt8(modeKeyFor(index))) == 1 {
                return
            }
        }
        throw SMCError.thermalLock
    }

    private func probeModeKey() throws {
        if (try? smc.readUInt8("F0Md")) != nil {
            modeKey = "F0Md"
            return
        }
        if (try? smc.readUInt8("F0md")) != nil {
            modeKey = "F0md"
        }
    }

    private func modeKeyFor(_ index: Int) -> String {
        "F\(index)\(modeKey.dropFirst(2))"
    }

    private func writeMode(_ index: Int, _ value: UInt8) throws {
        try smc.writeUInt8(modeKeyFor(index), value)
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

    private func key(_ index: Int, _ suffix: String) -> String {
        "F\(index)\(suffix)"
    }
}

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "io.statico.macotron", category: "helper")
    private let lock = NSLock()
    private let service = HelperService()
    private var connectionCount = 0

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard validate(connection) else {
            log.error("rejected unauthorized XPC client")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: MacotronHelperProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self] in
            self?.connectionInvalidated()
        }
        lock.lock()
        connectionCount += 1
        lock.unlock()
        connection.resume()
        return true
    }

    private func validate(_ connection: NSXPCConnection) -> Bool {
        // Runtime validation is required because any local process that finds the Mach service could otherwise drive the daemon as root.
        // launchd starts us with a relative argv[0]; use the live pid path.
        var path = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let pathLength = proc_pidpath(getpid(), &path, UInt32(path.count))
        guard pathLength > 0 else {
            log.error("validate: no helper path")
            return false
        }
        let ownPath = String(decoding: path.prefix(Int(pathLength)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var ownCode: SecStaticCode?
        var signingInformation: CFDictionary?
        guard SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: ownPath) as CFURL, [], &ownCode
        ) == errSecSuccess, let ownCode,
              SecCodeCopySigningInformation(
                  ownCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInformation
              ) == errSecSuccess,
              let team = (signingInformation as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String
        else {
            log.error("validate: helper has no Team ID")
            return false
        }

        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest else {
            log.error("validate: no client code for pid \(connection.processIdentifier)")
            return false
        }

        var requirement: SecRequirement?
        let requirementString =
            #"anchor apple generic and identifier "io.statico.macotron" and certificate leaf[subject.OU] = \#(team)"#
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            log.error("validate: bad requirement")
            return false
        }
        let status = SecCodeCheckValidity(guest, [], requirement)
        if status != errSecSuccess {
            log.error("validate: client failed requirement \(status)")
            return false
        }
        return true
    }

    private func connectionInvalidated() {
        lock.lock()
        connectionCount = max(0, connectionCount - 1)
        if connectionCount == 0 {
            service.restoreForFailsafe()
        }
        lock.unlock()
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: MacotronHelperService.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
