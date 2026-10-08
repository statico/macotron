import CryptoKit
import Foundation
import Testing
@testable import Modules

@Suite("BigUInt")
struct BigUIntTests {
    @Test("bytes round-trip, minimal and padded")
    func bytes() {
        let n = BigUInt(bytes: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(n.bytes() == [0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(n.bytes(count: 8) == [0, 0, 0, 1, 2, 3, 4, 5])
        #expect(BigUInt().bytes().isEmpty)
        #expect(BigUInt(hex: "0102030405") == n)
    }

    @Test("small arithmetic")
    func small() {
        #expect(BigUInt(4).power(BigUInt(13), modulus: BigUInt(497)) == BigUInt(445))
        #expect(BigUInt(UInt64.max) + BigUInt(1) == BigUInt(hex: "010000000000000000"))
        #expect(BigUInt(hex: "010000000000000000")! - BigUInt(1) == BigUInt(UInt64.max))
        #expect(BigUInt(1000) % BigUInt(7) == BigUInt(6))
        #expect(BigUInt(3) < BigUInt(hex: "0100000000")!)
    }

    @Test("multi-limb multiply and remainder match Python")
    func large() {
        let a = BigUInt(hex: String(repeating: "fedcba9876543210", count: 20))!
        let b = BigUInt(hex: String(repeating: "0f1e2d3c4b5a6978", count: 13))!
        #expect(a % b == BigUInt(hex: "14750c673c11970014750c673c11970014750c673c11970014750c673c11970014750c673c11970014750c673c1197100240b5eea154b8100240b5eea154b8100240b5eea154b8100240b5eea154b8100240b5eea154b8100240b5eea154b8100240b5eea154b80"))
        #expect((a * b).description.hasPrefix("0f0cf9d5a05a0299b8c6c3af8a540cb362808d89744e16cd0"))
        #expect((a * b).description.hasSuffix("b3446699de339a11999aacd00449a00780"))
        #expect((a * b) % a == BigUInt())
    }

    @Test("3072-bit modpow matches Python, and Fermat holds for the HAP prime")
    func modpow() {
        let n = SRPGroup.rfc5054_3072.prime
        let e = BigUInt(hex: String(repeating: "0123456789abcdef", count: 8))!
        #expect(BigUInt(5).power(e, modulus: n).description.hasPrefix("76d3515e1b69ce87d19e1b97cf61d366"))
        #expect(BigUInt(5).power(e, modulus: n).description.hasSuffix("b47de855d66c2bc5d6dcda6274c6b70a87a0eff9ff30129369641707babe1cf501271"))
        #expect(BigUInt(5).power(n - BigUInt(1), modulus: n) == BigUInt(1))
    }
}

@Suite("SRP")
struct SRPTests {
    /// RFC 5054 Appendix B: SHA-1 over the 1024-bit group.
    @Test("matches the RFC 5054 test vector")
    func rfc5054() throws {
        let client = SRPClient<Insecure.SHA1>(
            group: .rfc5054_1024, username: "alice", password: "password123",
            privateKey: BigUInt(hex: "60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393")!
        )
        let salt = BigUInt(hex: "BEB25379D1A8581EB5A727673A2441EE")!.bytes()
        let b = BigUInt(hex: """
            BD0C61512C692C0CB6D041FA01BB152D4916A1E77AF46AE105393011BAF38964DC46A0670DD125B95A981652236F99D9B681CBF87837EC99
            6C6DA04453728610D0C6DDB58B318885D7D82C7F8DEB75CE7BD4FBAA37089E6F9C6059F388838E7A00030B331EB76840910440B1B27AAEAE
            EB4012B7D7665238A8E3FB004B117B58
            """)!
        #expect(client.multiplier == BigUInt(hex: "7556AA045AEF2CDD07ABAF0F665C3E818913186F"))
        let x = client.passwordHash(salt: salt)
        #expect(x == BigUInt(hex: "94B7555AABE9127CC58CCF4993DB6CF84D16C124"))
        #expect(client.group.generator.power(x, modulus: client.group.prime) == BigUInt(hex: """
            7E273DE8696FFC4F4E337D05B4B375BEB0DDE1569E8FA00A9886D8129BADA1F1822223CA1A605B530E379BA4729FDC59F105B4787E5186F5
            C671085A1447B52A48CF1970B4FB6F8400BBF4CEBFBB168152E08AB5EA53D15C1AFF87B2B9DA6E04E058AD51CC72BFC9033B564E26480D78
            E955A5E29E7AB245DB2BE315E2099AFB
            """))
        #expect(client.publicKey == BigUInt(hex: """
            61D5E490F6F1B79547B0704C436F523DD0E560F0C64115BB72557EC44352E8903211C04692272D8B2D1A5358A2CF1B6E0BFCF99F921530EC
            8E39356179EAE45E42BA92AEACED825171E1E8B9AF6D9C03E1327F44BE087EF06530E69F66615261EEF54073CA11CF5858F0EDFDFE15EFEA
            B349EF5D76988A3672FAC47B0769447B
            """))
        #expect(client.scrambler(serverKey: b) == BigUInt(hex: "CE38B9593487DA98554ED47D70A7AE5F462EF019"))
        let session = try client.session(salt: salt, serverKey: b.bytes())
        #expect(session.premaster == BigUInt(hex: """
            B0DC82BABCF30674AE450C0287745E7990A3381F63B387AAF271A10D233861E359B48220F7C4693C9AE12B0A6F67809F0876E2D013800D6C
            41BB59B6D5979B5C00A172B4A2A5903A0BDCAF8A709585EB2AFAFA8F3499B200210DCC1F10EB33943CD67FC88A2F39A4BE5BEC4EC0A3212D
            C346D7E474B29EDE8A469FFECA686E5A
            """))
    }

    /// A local accessory computes the same secret from the other side, as an
    /// Apple TV does in pair-setup.
    @Test("3072-bit SHA-512 client agrees with a local server")
    func hapRoundTrip() throws {
        let group = SRPGroup.rfc5054_3072
        let salt = Array((0..<16).map { UInt8($0 * 7 + 1) })
        let client = SRPClient<SHA512>(group: group, username: "Pair-Setup", password: "1234",
                                       privateKey: BigUInt(bytes: (0..<32).map { UInt8($0 + 40) }))
        let n = group.prime
        let v = group.generator.power(client.passwordHash(salt: salt), modulus: n)
        let b = BigUInt(bytes: (0..<32).map { UInt8(200 - $0) })
        let serverKey = (client.multiplier * v + group.generator.power(b, modulus: n)) % n

        let session = try client.session(salt: salt, serverKey: serverKey.bytes())
        let u = client.scrambler(serverKey: serverKey)
        let serverSecret = ((client.publicKey * v.power(u, modulus: n)) % n).power(b, modulus: n)
        #expect(session.premaster == serverSecret)
        #expect(session.key == Array(SHA512.hash(data: serverSecret.bytes())))
        #expect(session.publicKey.count == 384)
        #expect(session.proof.count == 64)
        #expect(session.serverProof == Array(SHA512.hash(data: session.publicKey + session.proof + session.key)))

        let wrong = SRPClient<SHA512>(group: group, username: "Pair-Setup", password: "4321",
                                      privateKey: client.privateKey)
        #expect(try wrong.session(salt: salt, serverKey: serverKey.bytes()).premaster != serverSecret)
    }

    @Test("rejects a server key that is a multiple of N")
    func badKey() {
        let client = SRPClient<SHA512>(group: .rfc5054_3072, username: "Pair-Setup", password: "1234",
                                       privateKey: BigUInt(7))
        #expect(throws: (any Error).self) {
            try client.session(salt: [1], serverKey: SRPGroup.rfc5054_3072.prime.bytes())
        }
    }
}

/// Byte-exact cases from pyatv's tests/auth/test_hap_tlv8.py.
@Suite("TLV8")
struct TLV8Tests {
    @Test("encodes like pyatv")
    func encode() {
        #expect(TLV8.encode([(UInt8(10), Array("123".utf8))]) == [0x0A, 0x03, 0x31, 0x32, 0x33])
        #expect(TLV8.encode([(UInt8(1), Array("111".utf8)), (UInt8(4), Array("222".utf8))])
            == [0x01, 0x03, 0x31, 0x31, 0x31, 0x04, 0x03, 0x32, 0x32, 0x32])
        #expect(TLV8.encode([(UInt8(2), [UInt8](repeating: 0x31, count: 256))])
            == [0x02, 0xFF] + [UInt8](repeating: 0x31, count: 255) + [0x02, 0x01, 0x31])
    }

    @Test("decodes and joins fragments")
    func decode() {
        let long = [0x02, 0xFF] + [UInt8](repeating: 0x31, count: 255) + [0x02, 0x01, 0x31]
        #expect(TLV8.decode(long) == [2: [UInt8](repeating: 0x31, count: 256)])
        #expect(TLV8.decode([0x01, 0x03, 0x31, 0x31, 0x31, 0x04, 0x03, 0x32, 0x32, 0x32])
            == [1: Array("111".utf8), 4: Array("222".utf8)])
        #expect(TLV8.decode([0x01, 0x05, 0x00]) == nil)
    }
}

/// Byte-exact cases from pyatv's tests/support/test_opack.py.
@Suite("OPACK")
struct OPACKTests {
    private func hex(_ s: String) -> [UInt8] { BigUInt(hex: s)!.bytes() }

    @Test("scalars encode like pyatv")
    func scalars() {
        #expect(OPACK.bool(true).encoded() == [0x01])
        #expect(OPACK.bool(false).encoded() == [0x02])
        #expect(OPACK.null.encoded() == [0x04])
        #expect(OPACK.uuid(UUID(uuidString: "12345678-1234-5678-1234-567812345678")!).encoded()
            == [0x05] + hex("12345678123456781234567812345678"))
        #expect(OPACK.int(0).encoded() == [0x08])
        #expect(OPACK.int(0x27).encoded() == [0x2F])
        #expect(OPACK.int(0x28).encoded() == [0x30, 0x28])
        #expect(OPACK.int(0x1FF).encoded() == [0x31, 0xFF, 0x01])
        #expect(OPACK.int(0x1FFFFFF).encoded() == [0x32, 0xFF, 0xFF, 0xFF, 0x01])
        #expect(OPACK.int(0x1FFFFFFFFFFFFFF).encoded() == [0x33, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        #expect(OPACK.double(1.0).encoded() == [0x36, 0, 0, 0, 0, 0, 0, 0xF0, 0x3F])
        #expect(OPACK.string("abc").encoded() == [0x43, 0x61, 0x62, 0x63])
        #expect(OPACK.string(String(repeating: "a", count: 32)).encoded() == [0x60] + Array(repeating: 0x61, count: 32))
        #expect(OPACK.string(String(repeating: "a", count: 33)).encoded() == [0x61, 0x21] + Array(repeating: 0x61, count: 33))
        #expect(OPACK.string(String(repeating: "a", count: 256)).encoded() == [0x62, 0x00, 0x01] + Array(repeating: 0x61, count: 256))
        #expect(OPACK.data([0x12, 0x34, 0x56]).encoded() == [0x73, 0x12, 0x34, 0x56])
        #expect(OPACK.data(Array(repeating: 0x61, count: 33)).encoded() == [0x91, 0x21] + Array(repeating: 0x61, count: 33))
        #expect(OPACK.data(Array(repeating: 0x61, count: 65536)).encoded() == [0x93, 0x00, 0x00, 0x01, 0x00] + Array(repeating: 0x61, count: 65536))
    }

    @Test("containers and back-references encode like pyatv")
    func containers() {
        #expect(OPACK.array([1, "test", false]).encoded() == hex("d309447465737402"))
        #expect(OPACK.array([[true]]).encoded() == [0xD1, 0xD1, 0x01])
        #expect(OPACK.dict([("a", 12), (false, .null)]).encoded() == hex("e24161140204"))
        #expect(OPACK.array(Array(repeating: "a", count: 15)).encoded()
            == [0xDF, 0x41, 0x61] + Array(repeating: 0xA0, count: 14) + [0x03])
        #expect(OPACK.array(["foo", "bar", "foo", "bar"]).encoded() == hex("d443666f6f43626172a0a1"))
        #expect(OPACK.dict([("a", "b"), ("c", ["d": "a"]), ("d", true)]).encoded()
            == hex("e3416141624163e14164a0a301"))
    }

    @Test("decodes pyatv's samples, back-references and endless lists included")
    func decode() throws {
        #expect(try OPACK.decode(hex("e24161140204")) == .dict([("a", 12), (false, .null)]))
        #expect(try OPACK.decode([0x35, 0x00, 0x00, 0x80, 0x3F]) == .double(1.0))
        #expect(try OPACK.decode(hex("e3416141624163e14164a0a301"))
            == .dict([("a", "b"), ("c", ["d": "a"]), ("d", true)]))
        let endless = [0xDF, 0x41, 0x61] + [UInt8](repeating: 0xA0, count: 15) + [0x03]
        #expect(try OPACK.decode(endless) == .array(Array(repeating: "a", count: 16)))
        #expect(try OPACK.decode(hex("df30013002c10103")) == [1, 2, 2])
        #expect(try OPACK.decode(hex("df30013002c40100000003")) == [1, 2, 2])
        #expect(throws: OPACK.DecodeError.self) { try OPACK.decode([0x00]) }
        #expect(throws: OPACK.DecodeError.self) { try OPACK.decode([0x43, 0x61]) }
    }

    @Test("a Companion request round-trips")
    func roundTrip() throws {
        let message: OPACK = ["_i": "_hidC", "_t": 2, "_c": ["_hBtS": 1, "_hidC": 6], "_x": 41_234]
        let decoded = try OPACK.decode(message.encoded())
        #expect(decoded == message)
        #expect(decoded["_c"]?["_hidC"]?.int == 6)
        #expect(decoded["_x"]?.int == 41_234)
    }
}

@Suite("Companion crypto")
struct CompanionCryptoTests {
    @Test("session frames seal and open with counter nonces and the header as AAD")
    func cipherRoundTrip() throws {
        let a = SymmetricKey(size: .bits256)
        let b = SymmetricKey(size: .bits256)
        var client = CompanionCipher(outKey: a, inKey: b)
        var server = CompanionCipher(outKey: b, inKey: a)
        for text in ["first", "second", ""] {
            let frame = try client.seal(.encryptedOPACK, Array(text.utf8))
            #expect(frame[0] == 8)
            #expect(Int(frame[3]) == text.utf8.count + 16)
            #expect(try server.open(header: Array(frame[0..<4]), Array(frame[4...])) == Array(text.utf8))
        }
        // The other direction counts on its own.
        let reply = try server.seal(.encryptedOPACK, [1, 2, 3])
        #expect(try client.open(header: Array(reply[0..<4]), Array(reply[4...])) == [1, 2, 3])

        // A tampered header fails authentication.
        var tampered = try client.seal(.encryptedOPACK, [9])
        tampered[0] = 7
        #expect(throws: (any Error).self) { try server.open(header: Array(tampered[0..<4]), Array(tampered[4...])) }
    }

    @Test("nonces match pyatv's layouts")
    func nonces() {
        #expect(Array(CompanionCipher.nonce(1)) == [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(Array(HAPCrypto.nonce("PS-Msg05")) == [0, 0, 0, 0] + Array("PS-Msg05".utf8))
    }

    @Test("HAP labelled messages round-trip")
    func hapSeal() throws {
        let key = HAPCrypto.key(Array("secret".utf8), salt: "Pair-Setup-Encrypt-Salt", info: "Pair-Setup-Encrypt-Info")
        let sealed = try HAPCrypto.seal([1, 2, 3], key: key, label: "PS-Msg05")
        #expect(sealed.count == 19)
        #expect(try HAPCrypto.open(sealed, key: key, label: "PS-Msg05") == [1, 2, 3])
        #expect(throws: (any Error).self) { try HAPCrypto.open(sealed, key: key, label: "PS-Msg06") }
    }

    @Test("credentials use pyatv's string format")
    func credentials() {
        let creds = CompanionCredentials(deviceKey: Array(repeating: 0xAB, count: 32),
                                         clientSecret: Array(repeating: 0x01, count: 32),
                                         deviceID: Array("ATV".utf8), clientID: Array("me".utf8))
        let parts = creds.string.split(separator: ":")
        #expect(parts.count == 4)
        #expect(parts[2] == "415456")
        #expect(CompanionCredentials(string: creds.string) == creds)
        #expect(CompanionCredentials(string: "zz:00") == nil)
    }
}
