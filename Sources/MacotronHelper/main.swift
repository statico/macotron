// main.swift — the privileged half of fan control.
//
// Fan speed can be read by anyone, but writing it needs root, so everything
// that writes lives here in the launchd daemon and the app talks to it over
// XPC. The SMC keys, per fan index N:
//
//   FNAc  current rpm            FNMn / FNMx  the firmware's own rpm limits
//   FNTg  target rpm             FNMd         mode: 0 auto, 1 manual, 3 system
//   Ftst  diagnostic unlock, machine-wide
//
// The name of the mode key varies by machine (`FNMd` or `FNmd`), so it is
// probed once rather than assumed, and every rpm value is a little-endian
// float.
//
// What Macotron offers is a *floor*: the fans may not run slower than the
// user asked for, and macOS decides everything above that line. Holding a
// floor means taking a fan into manual mode and writing the floor as its
// target, which has two consequences this file spends most of its length on:
//
//   1. A fan in manual mode does exactly what it is told, so the floor is
//      also a ceiling. macOS cannot ramp past it however hot the machine
//      gets. `systemDemand` exists to notice that and get out of the way.
//   2. Manual mode is not ours by right. From the M3 generation on, the
//      thermal manager parks the fans in mode 3 and the firmware refuses the
//      mode write with SMC error 0x82 — hence `unlock` and the `Ftst` dance.
//
// Everything here re-asserts itself on a 2s timer, because the state is not
// ours to keep: sleep/wake clears `Ftst`, and the thermal manager can take a
// fan back at any point. The same timer is what makes the failsafes work —
// see `restoreForFailsafe`, which hands the fans back to macOS the moment the
// last client disconnects, so a crashed or quit Macotron can never leave a
// Mac with its fans pinned.
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
    private var forced: Set<Int> = []
    private var lastPeek: [Int: Date] = [:]
    /// How often a held fan is handed back to macOS to ask what it wants. The
    /// question is about heat, which moves in tens of seconds, and the answer
    /// costs a brief dip in speed, so it is not worth asking often.
    private static let peekInterval: TimeInterval = 30

    func setFanFloor(_ percent: Int, reply: @escaping (String?) -> Void) {
        lock.lock()
        floor = min(100, max(1, percent))
        log.info("setFanFloor \(self.floor ?? 0, privacy: .public)%")
        let error = apply()
        startTimer(error == nil)
        lock.unlock()
        reply(error)
    }

    func restoreFans(reply: @escaping (String?) -> Void) {
        lock.lock()
        log.info("restoreFans")
        floor = nil
        startTimer(false)
        let error = apply()
        lock.unlock()
        reply(error)
    }

    func shutdown(reply: @escaping (String?) -> Void) {
        lock.lock()
        log.info("shutdown requested")
        floor = nil
        startTimer(false)
        _ = apply()
        lock.unlock()
        reply(nil)
        // Let the reply travel before launchd notices we are gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
    }

    func identify(reply: @escaping (String) -> Void) {
        reply(MacotronHelperService.identity)
    }

    func restoreForFailsafe() {
        lock.lock()
        defer { lock.unlock() }
        log.info("failsafe: last client went away, releasing fans")
        floor = nil
        startTimer(false)
        if let error = apply() {
            log.error("failsafe restore failed: \(error, privacy: .public)")
        }
    }

    /// The floor is re-applied on a timer for as long as one is held, because
    /// nothing about manual mode survives on its own: sleep/wake clears the
    /// unlock, and the thermal manager can reclaim a fan whenever it likes.
    /// Re-asserting is also what notices a machine that has grown hot enough
    /// to want more air than the floor.
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
            // A forced fan sits at exactly our target, so a partial floor is
            // also a ceiling: while the machine works hard macOS may want more
            // air than the floor asks for, and holding it down there cooks the
            // Mac. Ask what macOS wants and stay out of its way when it wants
            // more. A floor at full speed cannot be a ceiling, so it never has
            // to ask — which matters, because asking costs a handback.
            let demand = floorRPM < fan.max ? systemDemand(fan.index, floor: floorRPM) : nil
            let force = FanFloor.shouldForce(demand: demand, floor: floorRPM)
            log.info(
                "fan \(fan.index, privacy: .public) rpm=\(Int(fan.rpm), privacy: .public) demand=\(demand.map { String(Int($0)) } ?? "?", privacy: .public) target=\(Int(floorRPM), privacy: .public) \(force ? "force" : "auto", privacy: .public)"
            )
            if force {
                try unlock(fan.index)
                try smc.writeRPM(key(fan.index, "Tg"), floorRPM)
                forced.insert(fan.index)
            } else {
                forced.remove(fan.index)
            }
        }
    }

    /// What macOS itself wants this fan to do. Only auto mode answers honestly
    /// — in manual mode the target key reads back the floor we wrote — so a
    /// forced fan has to be handed back first, and these fans spin down fast
    /// enough to hear. So: seldom, and only until thermalmonitord has written
    /// a number of its own, which it does on a 100ms cadence. A reading that
    /// still equals our own floor is not an answer; nil keeps the floor.
    private func systemDemand(_ index: Int, floor: Double) -> Double? {
        guard forced.contains(index) else { return try? smc.readRPM(key(index, "Tg")) }

        let now = Date()
        guard now.timeIntervalSince(lastPeek[index] ?? .distantPast) >= Self.peekInterval else {
            return nil
        }
        lastPeek[index] = now

        guard (try? writeMode(index, 0)) != nil else { return nil }
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.1)
            guard let value = try? smc.readRPM(key(index, "Tg")) else { continue }
            if abs(value - floor) >= 1 { return value }
        }
        return nil
    }

    /// Give every fan back to macOS. Mode 0 is what the machine boots with;
    /// `Ftst` is cleared too, so we leave nothing diagnostic switched on
    /// behind us.
    private func restoreAuto(count: Int) throws {
        forced.removeAll()
        lastPeek.removeAll()
        for index in 0..<count {
            try writeMode(index, 0)
        }
        if didUnlock {
            _ = try? smc.writeUInt8("Ftst", 0)
            didUnlock = false
        }
    }

    /// Take a fan into manual mode. The firmware may simply allow it, and on
    /// machines whose thermal manager holds the fans it will not: the way
    /// through is `Ftst`, the diagnostic flag, after which the mode write
    /// starts being accepted — usually within a second or two, hence the
    /// retry loop rather than a single attempt. Failing that, the floor
    /// genuinely cannot be held and the error says so.
    private func unlock(_ index: Int) throws {
        let mode = try? smc.readUInt8(modeKeyFor(index))
        if mode == 1 { return }
        // Mode 3 is the thermal manager holding the fan, and the firmware
        // rejects a plain mode write while it does. Only mode 0 is worth
        // asking politely; from mode 3 go straight for the diagnostic unlock.
        if mode != 3,
           (try? writeMode(index, 1)) != nil,
           (try? smc.readUInt8(modeKeyFor(index))) == 1 {
            return
        }
        log.info("fan \(index, privacy: .public) held in mode \(mode.map(String.init) ?? "?", privacy: .public), unlocking")
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

    /// Which spelling of the mode key this Mac uses. Cheap enough to redo on
    /// every apply, and it means a machine that names it `FNmd` needs no
    /// special case anywhere else.
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
        guard requireMacotron(connection) else {
            log.error("rejected XPC client: cannot build the signing requirement")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: MacotronHelperProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { [weak self] in
            self?.connectionInvalidated()
        }
        lock.lock()
        connectionCount += 1
        let count = connectionCount
        lock.unlock()
        log.info("client \(connection.processIdentifier, privacy: .public) connected, \(count, privacy: .public) open")
        connection.resume()
        return true
    }

    /// Any local process that finds the Mach service could otherwise drive the
    /// daemon as root, so every peer has to prove it is Macotron. XPC checks the
    /// requirement against the peer's signature as the kernel recorded it at
    /// launch; hand-rolling this with `SecCodeCheckValidity` re-reads the client
    /// off disk instead, which fails whenever the app has been updated since it
    /// started. Team ID comes from our own signature, so a rebuild under another
    /// team stays self-consistent.
    private func requireMacotron(_ connection: NSXPCConnection) -> Bool {
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
        connection.setCodeSigningRequirement(
            #"anchor apple generic and identifier "io.statico.macotron" and certificate leaf[subject.OU] = \#(team)"#
        )
        return true
    }

    private func connectionInvalidated() {
        lock.lock()
        connectionCount = max(0, connectionCount - 1)
        log.info("client disconnected, \(self.connectionCount, privacy: .public) open")
        let idle = connectionCount == 0
        if idle {
            service.restoreForFailsafe()
        }
        lock.unlock()
        // Exit when nobody is left. launchd starts us on demand, so staying
        // resident means an updated app keeps talking to the daemon it shipped
        // with weeks ago -- the fan bug fixed in the app is still live in here.
        guard idle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            lock.lock()
            let stillIdle = connectionCount == 0
            lock.unlock()
            if stillIdle { exit(0) }
        }
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: MacotronHelperService.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
