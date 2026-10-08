import CryptoKit
import Foundation
import Network

// Apple's Companion protocol, the one the iPhone remote uses, following pyatv's
// protocols/companion and auth/hap_srp.py. A connection pairs once with the
// PIN the TV shows (HAP pair-setup: SRP, then Ed25519 identities), and every
// connection after that runs HAP pair-verify to derive ChaCha20-Poly1305 keys.

/// The frame types this client uses. Every frame is a 1-byte type and a 3-byte
/// big-endian payload length, then the payload.
enum CompanionFrame: UInt8 {
    case pairSetupStart = 3
    case pairSetupNext = 4
    case pairVerifyStart = 5
    case pairVerifyNext = 6
    case encryptedOPACK = 8

    func header(length: Int) -> [UInt8] {
        [rawValue, UInt8(truncatingIfNeeded: length >> 16), UInt8(truncatingIfNeeded: length >> 8),
         UInt8(truncatingIfNeeded: length)]
    }
}

/// What a pairing leaves behind: the TV's identity and our own. Stored as
/// pyatv's credential string, `ltpk:ltsk:atv_id:client_id` in hex, so a pairing
/// made here also works with `atvremote --companion-credentials`.
struct CompanionCredentials: Equatable {
    let deviceKey: [UInt8]
    let clientSecret: [UInt8]
    let deviceID: [UInt8]
    let clientID: [UInt8]

    var string: String {
        [deviceKey, clientSecret, deviceID, clientID].map(Self.hex).joined(separator: ":")
    }

    init(deviceKey: [UInt8], clientSecret: [UInt8], deviceID: [UInt8], clientID: [UInt8]) {
        self.deviceKey = deviceKey
        self.clientSecret = clientSecret
        self.deviceID = deviceID
        self.clientID = clientID
    }

    init?(string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false).map { Self.bytes(String($0)) }
        guard parts.count == 4, let k = parts[0], let s = parts[1], let d = parts[2], let c = parts[3],
              k.count == 32, s.count == 32, !d.isEmpty, !c.isEmpty else { return nil }
        self.init(deviceKey: k, clientSecret: s, deviceID: d, clientID: c)
    }

    private static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

    private static func bytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let byte = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(byte)
            i = j
        }
        return out
    }
}

/// HAP's key derivation and its fixed-label ChaCha20-Poly1305 messages.
enum HAPCrypto {
    static func key(_ secret: [UInt8], salt: String, info: String) -> SymmetricKey {
        HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), salt: Data(salt.utf8),
                               info: Data(info.utf8), outputByteCount: 32)
    }

    /// Pair-setup and pair-verify messages use an 8-byte ASCII label such as
    /// "PS-Msg05" as the nonce, left-padded with four zero bytes.
    static func nonce(_ label: String) -> ChaChaPoly.Nonce {
        try! ChaChaPoly.Nonce(data: [0, 0, 0, 0] + Array(label.utf8))
    }

    static func seal(_ plain: [UInt8], key: SymmetricKey, label: String) throws -> [UInt8] {
        let box = try ChaChaPoly.seal(plain, using: key, nonce: nonce(label))
        return Array(box.ciphertext + box.tag)
    }

    static func open(_ sealed: [UInt8], key: SymmetricKey, label: String) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw CompanionError.protocolError("short encrypted data") }
        let box = try ChaChaPoly.SealedBox(nonce: nonce(label), ciphertext: sealed.dropLast(16),
                                           tag: sealed.suffix(16))
        return Array(try ChaChaPoly.open(box, using: key))
    }
}

/// Session encryption after pair-verify. The nonce is a per-direction counter
/// as 12 little-endian bytes, and the 4-byte frame header is the AAD.
struct CompanionCipher {
    let outKey: SymmetricKey
    let inKey: SymmetricKey
    private var outCounter: UInt64 = 0
    private var inCounter: UInt64 = 0

    init(outKey: SymmetricKey, inKey: SymmetricKey) {
        self.outKey = outKey
        self.inKey = inKey
    }

    static func nonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        try! ChaChaPoly.Nonce(data: withUnsafeBytes(of: counter.littleEndian) { Array($0) } + [0, 0, 0, 0])
    }

    /// Returns the frame header and the sealed payload.
    mutating func seal(_ frame: CompanionFrame, _ plain: [UInt8]) throws -> [UInt8] {
        let header = frame.header(length: plain.count + 16)
        let box = try ChaChaPoly.seal(plain, using: outKey, nonce: Self.nonce(outCounter), authenticating: header)
        outCounter += 1
        return header + box.ciphertext + box.tag
    }

    mutating func open(header: [UInt8], _ sealed: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw CompanionError.protocolError("short frame") }
        let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(inCounter), ciphertext: sealed.dropLast(16),
                                           tag: sealed.suffix(16))
        inCounter += 1
        return Array(try ChaChaPoly.open(box, using: inKey, authenticating: header))
    }
}

enum CompanionError: Error, CustomStringConvertible {
    case timeout
    case closed(String)
    case protocolError(String)
    case pairing(String)

    var description: String {
        switch self {
        case .timeout: "Apple TV did not answer"
        case let .closed(why): "Connection closed: \(why)"
        case let .protocolError(why): "Protocol error: \(why)"
        case let .pairing(why): why
        }
    }

    /// HAP error codes (HAP spec 5.4) as a person would want to read them.
    static func pairing(code: UInt8) -> CompanionError {
        switch code {
        case 2: .pairing("Wrong PIN")
        case 3: .pairing("Apple TV asked to wait before pairing again")
        case 4: .pairing("Apple TV cannot pair with more devices")
        case 5: .pairing("Too many PIN attempts")
        case 6: .pairing("Apple TV is not accepting pairing now")
        case 7: .pairing("Apple TV is busy pairing with another device")
        default: .pairing("Pairing failed (error \(code))")
        }
    }
}

/// One TCP connection to an Apple TV's companion-link port. Calls block until
/// the TV answers, so run them off the main thread, one caller at a time.
final class CompanionLink: @unchecked Sendable {
    static let timeout: TimeInterval = 5

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "io.statico.macotron.companion")
    private let stateLock = NSLock()
    private var failed: String?
    private var buffer: [UInt8] = []
    private var cipher: CompanionCipher?
    private var xid = Int.random(in: 0...0xFFFF)

    init(host: String, port: Int) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 0,
                                  using: .tcp)
    }

    var isAlive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return failed == nil
    }

    private func fail(_ why: String) {
        stateLock.lock()
        if failed == nil { failed = why }
        stateLock.unlock()
    }

    func open() throws {
        let ready = DispatchSemaphore(value: 0)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: ready.signal()
            case let .waiting(error), let .failed(error):
                self?.fail(error.localizedDescription)
                ready.signal()
            case .cancelled:
                self?.fail("cancelled")
                ready.signal()
            default: break
            }
        }
        connection.start(queue: queue)
        if ready.wait(timeout: .now() + Self.timeout) == .timedOut { fail("timed out connecting") }
        stateLock.lock()
        let why = failed
        stateLock.unlock()
        if let why {
            connection.cancel()
            throw CompanionError.closed(why)
        }
    }

    func close() {
        fail("closed")
        connection.cancel()
    }

    // MARK: - Frames

    private func write(_ bytes: [UInt8]) throws {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var sendError: NWError?
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            sendError = error
            done.signal()
        })
        if done.wait(timeout: .now() + Self.timeout) == .timedOut {
            close()
            throw CompanionError.timeout
        }
        if let sendError {
            close()
            throw CompanionError.closed(sendError.localizedDescription)
        }
    }

    private func send(_ frame: CompanionFrame, _ message: OPACK) throws {
        let plain = message.encoded()
        if var cipher {
            let sealed = try cipher.seal(frame, plain)
            self.cipher = cipher
            try write(sealed)
        } else {
            try write(frame.header(length: plain.count) + plain)
        }
    }

    /// The next whole frame, decrypted once the session is encrypted. A timeout
    /// closes the link, since a read still in flight would lose its bytes.
    private func receiveFrame(until deadline: Date) throws -> (UInt8, [UInt8]) {
        while true {
            if buffer.count >= 4 {
                let length = Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
                if buffer.count >= 4 + length {
                    let header = Array(buffer[0..<4])
                    var payload = Array(buffer[4..<(4 + length)])
                    buffer.removeFirst(4 + length)
                    if var cipher, !payload.isEmpty {
                        payload = try cipher.open(header: header, payload)
                        self.cipher = cipher
                    }
                    return (header[0], payload)
                }
            }

            let got = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var chunk: Data?
            nonisolated(unsafe) var why: String?
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                chunk = data
                if let error { why = error.localizedDescription } else if complete, data?.isEmpty ?? true {
                    why = "Apple TV closed the connection"
                }
                got.signal()
            }
            if got.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .timedOut {
                close()
                throw CompanionError.timeout
            }
            if let chunk { buffer += chunk }
            if let why, chunk?.isEmpty ?? true {
                close()
                throw CompanionError.closed(why)
            }
        }
    }

    /// Sends an OPACK message with the next transaction id (`_x`) appended.
    private func stamp(_ message: OPACK) -> (OPACK, Int) {
        guard case var .dict(pairs) = message else { return (message, xid) }
        let id = xid
        xid += 1
        pairs.append(("_x", .int(id)))
        return (.dict(pairs), id)
    }

    /// One pair-setup or pair-verify round trip. The TV answers both *_Start
    /// and *_Next with a *_Next frame, so that is what this waits for.
    private func exchangeAuth(_ frame: CompanionFrame, _ tlv: [UInt8], _ extra: [(OPACK, OPACK)] = [])
        throws -> [UInt8: [UInt8]] {
        let reply: CompanionFrame = frame == .pairSetupStart || frame == .pairSetupNext ? .pairSetupNext : .pairVerifyNext
        try send(frame, stamp(.dict([("_pd", .data(tlv))] + extra)).0)
        let deadline = Date().addingTimeInterval(Self.timeout)
        while true {
            let (type, payload) = try receiveFrame(until: deadline)
            guard type == reply.rawValue else { continue }
            guard let data = try OPACK.decode(payload)["_pd"]?.data, let fields = TLV8.decode(data) else {
                throw CompanionError.protocolError("no pairing data")
            }
            if let code = fields[TLV8.Tag.error.rawValue]?.first { throw CompanionError.pairing(code: code) }
            return fields
        }
    }

    /// Sends a request (`_t` 2) and waits for the response (`_t` 3) with the
    /// same transaction id, skipping events the TV pushes in between.
    @discardableResult
    func request(_ identifier: String, _ content: OPACK) throws -> OPACK {
        let (message, id) = stamp(["_i": .string(identifier), "_t": 2, "_c": content])
        try send(.encryptedOPACK, message)
        let deadline = Date().addingTimeInterval(Self.timeout)
        while true {
            let (type, payload) = try receiveFrame(until: deadline)
            guard type == CompanionFrame.encryptedOPACK.rawValue else { continue }
            let reply = try OPACK.decode(payload)
            guard reply["_t"]?.int == 3, reply["_x"]?.int == id else { continue }
            if let error = reply["_em"] {
                throw CompanionError.protocolError("\(identifier) failed: \(error.string ?? "\(error)")")
            }
            return reply
        }
    }

    // MARK: - Pair-setup (pyatv CompanionPairSetupProcedure)

    struct SetupChallenge {
        let salt: [UInt8]
        let serverKey: [UInt8]
    }

    /// M1: asks to pair. The TV shows a PIN and answers with M2.
    func pairSetupStart() throws -> SetupChallenge {
        let m2 = try exchangeAuth(.pairSetupStart, TLV8.encode([(.method, [0]), (.state, [1])]), [("_pwTy", 1)])
        guard let salt = m2[TLV8.Tag.salt.rawValue], let key = m2[TLV8.Tag.publicKey.rawValue] else {
            throw CompanionError.protocolError("no salt or key in M2")
        }
        return SetupChallenge(salt: salt, serverKey: key)
    }

    /// M3 to M6: proves the PIN, then swaps long-term Ed25519 identities.
    func pairSetupFinish(pin: String, challenge: SetupChallenge, name: String) throws -> CompanionCredentials {
        let seed = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
        let srp = SRPClient<SHA512>(group: .rfc5054_3072, username: "Pair-Setup", password: pin,
                                    privateKey: BigUInt(bytes: seed))
        let session: SRPClient<SHA512>.Session
        do {
            session = try srp.session(salt: challenge.salt, serverKey: challenge.serverKey)
        } catch {
            throw CompanionError.protocolError("bad SRP key from Apple TV")
        }

        let m4 = try exchangeAuth(.pairSetupNext, TLV8.encode([
            (.state, [3]), (.publicKey, session.publicKey), (.proof, session.proof),
        ]), [("_pwTy", 1)])
        guard m4[TLV8.Tag.proof.rawValue] == session.serverProof else {
            throw CompanionError.pairing("Apple TV proof did not match")
        }

        let signing = Curve25519.Signing.PrivateKey()
        let ltpk = Array(signing.publicKey.rawRepresentation)
        let clientID = Array(UUID().uuidString.lowercased().utf8)
        let controllerX = HAPCrypto.key(session.key, salt: "Pair-Setup-Controller-Sign-Salt",
                                        info: "Pair-Setup-Controller-Sign-Info")
        let encryptKey = HAPCrypto.key(session.key, salt: "Pair-Setup-Encrypt-Salt", info: "Pair-Setup-Encrypt-Info")
        let signed = controllerX.withUnsafeBytes { Array($0) } + clientID + ltpk
        let inner = TLV8.encode([
            (.identifier, clientID),
            (.publicKey, ltpk),
            (.signature, Array(try signing.signature(for: signed))),
            (.name, (["name": .string(name)] as OPACK).encoded()),
        ])
        let m6 = try exchangeAuth(.pairSetupNext, TLV8.encode([
            (.state, [5]), (.encryptedData, try HAPCrypto.seal(inner, key: encryptKey, label: "PS-Msg05")),
        ]), [("_pwTy", 1)])

        guard let sealed = m6[TLV8.Tag.encryptedData.rawValue],
              let device = TLV8.decode(try HAPCrypto.open(sealed, key: encryptKey, label: "PS-Msg06")),
              let deviceID = device[TLV8.Tag.identifier.rawValue],
              let deviceKey = device[TLV8.Tag.publicKey.rawValue], deviceKey.count == 32 else {
            throw CompanionError.protocolError("bad M6")
        }
        // ponytail: like pyatv, the TV's M6 signature is not checked; M6 is
        // already sealed with the PIN-derived key. Check it if that changes.
        return CompanionCredentials(deviceKey: deviceKey, clientSecret: Array(signing.rawRepresentation),
                                    deviceID: deviceID, clientID: clientID)
    }

    // MARK: - Pair-verify and session (pyatv CompanionPairVerifyProcedure, CompanionAPI.connect)

    func pairVerify(_ credentials: CompanionCredentials) throws {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ourKey = Array(ephemeral.publicKey.rawRepresentation)
        let m2: [UInt8: [UInt8]]
        do {
            m2 = try exchangeAuth(.pairVerifyStart, TLV8.encode([(.state, [1]), (.publicKey, ourKey)]),
                                  [("_auTy", 4)])
        } catch CompanionError.pairing {
            throw CompanionError.pairing("Apple TV refused this Mac's pairing. Pair again.")
        }
        guard let theirKey = m2[TLV8.Tag.publicKey.rawValue], let sealed = m2[TLV8.Tag.encryptedData.rawValue] else {
            throw CompanionError.protocolError("no key in verify M2")
        }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(
            with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirKey))
        let secret = shared.withUnsafeBytes { Array($0) }
        let verifyKey = HAPCrypto.key(secret, salt: "Pair-Verify-Encrypt-Salt", info: "Pair-Verify-Encrypt-Info")

        guard let device = TLV8.decode(try HAPCrypto.open(sealed, key: verifyKey, label: "PV-Msg02")),
              let identifier = device[TLV8.Tag.identifier.rawValue],
              let signature = device[TLV8.Tag.signature.rawValue] else {
            throw CompanionError.protocolError("bad verify M2")
        }
        guard identifier == credentials.deviceID else {
            throw CompanionError.pairing("A different Apple TV answered. Pair again.")
        }
        let deviceKey = try Curve25519.Signing.PublicKey(rawRepresentation: credentials.deviceKey)
        guard deviceKey.isValidSignature(signature, for: theirKey + identifier + ourKey) else {
            throw CompanionError.pairing("Apple TV signature did not verify. Pair again.")
        }

        let ours = try Curve25519.Signing.PrivateKey(rawRepresentation: credentials.clientSecret)
        let proof = TLV8.encode([
            (.identifier, credentials.clientID),
            (.signature, Array(try ours.signature(for: ourKey + credentials.clientID + theirKey))),
        ])
        _ = try exchangeAuth(.pairVerifyNext, TLV8.encode([
            (.state, [3]), (.encryptedData, try HAPCrypto.seal(proof, key: verifyKey, label: "PV-Msg03")),
        ]))

        cipher = CompanionCipher(outKey: HAPCrypto.key(secret, salt: "", info: "ClientEncrypt-main"),
                                 inKey: HAPCrypto.key(secret, salt: "", info: "ServerEncrypt-main"))
    }

    /// The handshake pyatv's CompanionAPI.connect does before any key press.
    func startSession(_ credentials: CompanionCredentials, name: String) throws {
        // A stable 6-byte id per pairing, standing in for pyatv's rp_id.
        let rpID = SHA256.hash(data: credentials.clientID).prefix(6).map { String(format: "%02x", $0) }.joined()
        try request("_systemInfo", [
            "_bf": 0, "_cf": 512, "_clFl": 128,
            "_i": .string(rpID),
            "_idsID": .data(credentials.clientID),
            "_pubID": "FF:70:79:61:74:76",
            "_sf": 256, "_sv": "170.18",
            "model": "iPhone10,6",
            "name": .string(name),
        ])
        try request("_touchStart", ["_height": 1000.0, "_tFl": 0, "_width": 1000.0])
        try request("_sessionStart", ["_srvT": "com.apple.tvremoteservices", "_sid": .int(Int(UInt32.random(in: .min ... .max)))])
        try request("_tiStart", [:])
    }
}
