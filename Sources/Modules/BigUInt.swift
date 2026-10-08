import Foundation

/// Just enough unsigned big-integer arithmetic for SRP: Apple ships no public
/// bignum or SRP API. Limbs are little-endian UInt32 with no high zero limbs.
// ponytail: schoolbook multiply and Knuth division, about 0.3 s per pairing
// in a debug build. Montgomery form if this ever runs per key press.
struct BigUInt: Equatable, Comparable, CustomStringConvertible {
    private(set) var limbs: [UInt32]

    init(_ value: UInt64 = 0) {
        limbs = [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
        normalize()
    }

    private init(limbs: [UInt32]) {
        self.limbs = limbs
        normalize()
    }

    /// Big-endian bytes, as SRP puts numbers on the wire.
    init<Bytes: Sequence>(bytes: Bytes) where Bytes.Element == UInt8 {
        var out: [UInt32] = []
        var limb: UInt32 = 0
        var shift: UInt32 = 0
        for byte in bytes.reversed() {
            limb |= UInt32(byte) << shift
            shift += 8
            if shift == 32 {
                out.append(limb)
                limb = 0
                shift = 0
            }
        }
        if shift > 0 { out.append(limb) }
        self.init(limbs: out)
    }

    init?(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
        var bytes: [UInt8] = []
        var chars = Array(digits)
        if chars.count % 2 == 1 { chars.insert("0", at: 0) }
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes: bytes)
    }

    /// Big-endian bytes, minimal unless `count` asks for left zero padding.
    func bytes(count: Int = 0) -> [UInt8] {
        var out: [UInt8] = []
        for limb in limbs.reversed() {
            out += [UInt8(limb >> 24), UInt8(truncatingIfNeeded: limb >> 16),
                    UInt8(truncatingIfNeeded: limb >> 8), UInt8(truncatingIfNeeded: limb)]
        }
        let minimal = Array(out.drop { $0 == 0 })
        return Array(repeating: 0, count: max(0, count - minimal.count)) + minimal
    }

    var isZero: Bool { limbs.isEmpty }
    var bitWidth: Int { limbs.isEmpty ? 0 : limbs.count * 32 - limbs.last!.leadingZeroBitCount }
    var description: String { bytes().map { String(format: "%02x", $0) }.joined() }

    func bit(_ i: Int) -> Bool {
        let limb = i / 32
        return limb < limbs.count && limbs[limb] & (1 << UInt32(i % 32)) != 0
    }

    private mutating func normalize() {
        while limbs.last == 0 { limbs.removeLast() }
    }

    static func < (a: BigUInt, b: BigUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] {
            return a.limbs[i] < b.limbs[i]
        }
        return false
    }

    static func + (a: BigUInt, b: BigUInt) -> BigUInt {
        var out = [UInt32](repeating: 0, count: max(a.limbs.count, b.limbs.count) + 1)
        var carry: UInt64 = 0
        for i in 0..<out.count - 1 {
            let sum = UInt64(i < a.limbs.count ? a.limbs[i] : 0)
                + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
            out[i] = UInt32(truncatingIfNeeded: sum)
            carry = sum >> 32
        }
        out[out.count - 1] = UInt32(carry)
        return BigUInt(limbs: out)
    }

    /// `a - b` for `a >= b`.
    static func - (a: BigUInt, b: BigUInt) -> BigUInt {
        precondition(a >= b, "BigUInt subtraction underflow")
        var out = a.limbs
        var borrow: Int64 = 0
        for i in 0..<out.count {
            let diff = Int64(out[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
            out[i] = UInt32(truncatingIfNeeded: diff)
            borrow = diff < 0 ? 1 : 0
        }
        return BigUInt(limbs: out)
    }

    static func * (a: BigUInt, b: BigUInt) -> BigUInt {
        if a.isZero || b.isZero { return BigUInt() }
        // Raw pointers and while loops in the hot loops here and in %: in a
        // debug build, Array indexing and ranges made a pairing take ~10 s.
        var out = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        let na = a.limbs.count, nb = b.limbs.count
        out.withUnsafeMutableBufferPointer { out in
            a.limbs.withUnsafeBufferPointer { a in
                b.limbs.withUnsafeBufferPointer { b in
                    let o = out.baseAddress!, pa = a.baseAddress!, pb = b.baseAddress!
                    var i = 0
                    while i < na {
                        var carry: UInt64 = 0
                        let ai = UInt64(pa[i])
                        var j = 0
                        while j < nb {
                            let t = ai &* UInt64(pb[j]) &+ UInt64(o[i &+ j]) &+ carry
                            o[i &+ j] = UInt32(truncatingIfNeeded: t)
                            carry = t &>> 32
                            j &+= 1
                        }
                        o[i &+ nb] = UInt32(truncatingIfNeeded: carry)
                        i &+= 1
                    }
                }
            }
        }
        return BigUInt(limbs: out)
    }

    /// Remainder by Knuth's Algorithm D (TAOCP 4.3.1).
    static func % (a: BigUInt, m: BigUInt) -> BigUInt {
        precondition(!m.isZero, "BigUInt division by zero")
        if a < m { return a }
        let n = m.limbs.count
        if n == 1 {
            let d = UInt64(m.limbs[0])
            var r: UInt64 = 0
            for limb in a.limbs.reversed() { r = ((r << 32) | UInt64(limb)) % d }
            return BigUInt(r)
        }

        // Normalize so the divisor's top limb has its high bit set.
        let s = UInt32(m.limbs[n - 1].leadingZeroBitCount)
        let v = shiftLeft(m.limbs, s, extra: false)
        var u = shiftLeft(a.limbs, s, extra: true)
        let base: UInt64 = 1 << 32

        var j = a.limbs.count - n
        u.withUnsafeMutableBufferPointer { u in
            v.withUnsafeBufferPointer { v in
                let u = u.baseAddress!, v = v.baseAddress!
                let vTop = UInt64(v[n - 1]), vNext = UInt64(v[n - 2])
                while j >= 0 {
                    let top = (UInt64(u[j + n]) << 32) | UInt64(u[j + n - 1])
                    var qhat = top / vTop
                    var rhat = top % vTop
                    while qhat >= base || qhat * vNext > ((rhat << 32) | UInt64(u[j + n - 2])) {
                        qhat -= 1
                        rhat += vTop
                        if rhat >= base { break }
                    }

                    var borrow: UInt64 = 0
                    var carry: UInt64 = 0
                    var i = 0
                    while i < n {
                        let p = qhat &* UInt64(v[i]) &+ carry
                        carry = p &>> 32
                        let t = UInt64(u[i &+ j]) &- borrow &- (p & 0xFFFF_FFFF)
                        u[i &+ j] = UInt32(truncatingIfNeeded: t)
                        borrow = t &>> 63
                        i &+= 1
                    }
                    let t = Int64(u[j + n]) - Int64(borrow) - Int64(carry)
                    u[j + n] = UInt32(truncatingIfNeeded: t)

                    if t < 0 {
                        // qhat was one too large: add the divisor back once.
                        var c: UInt64 = 0
                        i = 0
                        while i < n {
                            let sum = UInt64(u[i &+ j]) &+ UInt64(v[i]) &+ c
                            u[i &+ j] = UInt32(truncatingIfNeeded: sum)
                            c = sum &>> 32
                            i &+= 1
                        }
                        u[j + n] = UInt32(truncatingIfNeeded: UInt64(u[j + n]) + c)
                    }
                    j -= 1
                }
            }
        }

        // The remainder is the low n limbs, shifted back.
        var r = [UInt32](repeating: 0, count: n)
        for i in 0..<n {
            let high = i + 1 < n ? UInt64(u[i + 1]) << 32 : 0
            r[i] = UInt32(truncatingIfNeeded: (high | UInt64(u[i])) >> UInt64(s))
        }
        return BigUInt(limbs: r)
    }

    private static func shiftLeft(_ x: [UInt32], _ s: UInt32, extra: Bool) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: x.count + (extra ? 1 : 0))
        var carry: UInt32 = 0
        for i in 0..<x.count {
            out[i] = (x[i] << s) | carry
            carry = s == 0 ? 0 : x[i] >> (32 - s)
        }
        if extra { out[x.count] = carry }
        return out
    }

    /// `self^exponent mod modulus`, square-and-multiply from the top bit.
    func power(_ exponent: BigUInt, modulus: BigUInt) -> BigUInt {
        var result = BigUInt(1) % modulus
        let base = self % modulus
        for i in stride(from: exponent.bitWidth - 1, through: 0, by: -1) {
            result = (result * result) % modulus
            if exponent.bit(i) { result = (result * base) % modulus }
        }
        return result
    }
}
