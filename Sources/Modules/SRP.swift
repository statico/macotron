import CryptoKit
import Foundation

/// An SRP group: a safe prime and its generator (RFC 5054 Appendix A).
struct SRPGroup {
    let prime: BigUInt
    let generator: BigUInt

    /// The 1024-bit group, used only by the RFC 5054 test vector.
    static let rfc5054_1024 = SRPGroup(prime: BigUInt(hex: """
        EEAF0AB9ADB38DD69C33F80AFA8FC5E860726187 75FF3C0B9EA2314C9C256576D674DF7496EA81D3
        383B4813D692C6E0E0D5D8E250B98BE48E495C1D 6089DAD15DC7D7B46154D6B6CE8EF4AD69B15D49
        82559B297BCF1885C529F566660E57EC68EDBC3C 05726CC02FD4CBF4976EAA9AFD5138FE8376435B
        9FC61D2FC0EB06E3
        """)!, generator: BigUInt(2))

    /// The 3072-bit group HomeKit pairing uses.
    static let rfc5054_3072 = SRPGroup(prime: BigUInt(hex: """
        FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22
        514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6
        F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D
        C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB
        9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C180E8603
        9B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510
        15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7D
        B3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6BF12FFA06D98A0864
        D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB31
        43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF
        """)!, generator: BigUInt(5))
}

/// The client half of SRP-6a. It follows srptools, which pyatv pairs Apple TVs
/// with: k = H(N | PAD(g)), u = H(PAD(A) | PAD(B)), x = H(s | H(I ":" P)),
/// K = H(S), M1 = H(H(N) ^ H(g) | H(I) | s | A | B | K), M2 = H(A | M1 | K),
/// with every number other than the padded ones in minimal big-endian bytes.
struct SRPClient<Hash: HashFunction> {
    let group: SRPGroup
    let username: String
    let password: String
    let privateKey: BigUInt

    var publicKey: BigUInt { group.generator.power(privateKey, modulus: group.prime) }

    struct Session {
        let publicKey: [UInt8]
        let premaster: BigUInt
        let key: [UInt8]
        let proof: [UInt8]
        let serverProof: [UInt8]
    }

    enum Failure: Error { case badServerKey }

    static func hash(_ parts: [UInt8]...) -> [UInt8] {
        var h = Hash()
        for part in parts { h.update(data: part) }
        return Array(h.finalize())
    }

    private var width: Int { group.prime.bytes().count }
    private func pad(_ n: BigUInt) -> [UInt8] { n.bytes(count: width) }

    var multiplier: BigUInt { BigUInt(bytes: Self.hash(group.prime.bytes(), pad(group.generator))) }

    func passwordHash(salt: [UInt8]) -> BigUInt {
        BigUInt(bytes: Self.hash(salt, Self.hash(Array("\(username):\(password)".utf8))))
    }

    func scrambler(serverKey: BigUInt) -> BigUInt {
        BigUInt(bytes: Self.hash(pad(publicKey), pad(serverKey)))
    }

    func session(salt: [UInt8], serverKey: [UInt8]) throws -> Session {
        let n = group.prime
        let b = BigUInt(bytes: serverKey)
        guard !(b % n).isZero else { throw Failure.badServerKey }
        let a = publicKey
        let x = passwordHash(salt: salt)
        let u = scrambler(serverKey: b)
        let kv = (multiplier * group.generator.power(x, modulus: n)) % n
        let base = (b % n + n - kv) % n
        let s = base.power(privateKey + u * x, modulus: n)
        let key = Self.hash(s.bytes())

        let hn = Self.hash(n.bytes())
        let hg = Self.hash(group.generator.bytes())
        let xor = BigUInt(bytes: zip(hn, hg).map { $0 ^ $1 }).bytes()
        let proof = Self.hash(xor, Self.hash(Array(username.utf8)), salt, a.bytes(), b.bytes(), key)
        let serverProof = Self.hash(a.bytes(), proof, key)
        return Session(publicKey: a.bytes(), premaster: s, key: key, proof: proof, serverProof: serverProof)
    }
}
