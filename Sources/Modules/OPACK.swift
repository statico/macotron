import Foundation

/// Apple's OPACK serialization, as the Companion protocol uses it. It follows
/// pyatv's opack.py byte for byte, including the back-references that replace
/// a repeated value with its index in the list of values seen so far.
indirect enum OPACK: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data([UInt8])
    case uuid(UUID)
    case array([OPACK])
    /// Ordered, because the order is part of the encoding.
    case dict([(OPACK, OPACK)])

    struct DecodeError: Error {}

    static func == (a: OPACK, b: OPACK) -> Bool {
        switch (a, b) {
        case (.null, .null): true
        case let (.bool(x), .bool(y)): x == y
        case let (.int(x), .int(y)): x == y
        case let (.double(x), .double(y)): x == y
        case let (.string(x), .string(y)): x == y
        case let (.data(x), .data(y)): x == y
        case let (.uuid(x), .uuid(y)): x == y
        case let (.array(x), .array(y)): x == y
        case let (.dict(x), .dict(y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }

    subscript(key: String) -> OPACK? {
        guard case let .dict(pairs) = self else { return nil }
        return pairs.first { $0.0 == .string(key) }?.1
    }

    var int: Int? { if case let .int(v) = self { v } else { nil } }
    var string: String? { if case let .string(v) = self { v } else { nil } }
    var data: [UInt8]? { if case let .data(v) = self { v } else { nil } }

    // MARK: - Encoding

    func encoded() -> [UInt8] {
        var seen: [[UInt8]] = []
        return encode(&seen)
    }

    private func encode(_ seen: inout [[UInt8]]) -> [UInt8] {
        var out: [UInt8]
        switch self {
        case .null: out = [0x04]
        case let .bool(v): out = [v ? 0x01 : 0x02]
        case let .uuid(v): out = [0x05] + withUnsafeBytes(of: v.uuid) { Array($0) }
        case let .int(v):
            let u = UInt64(bitPattern: Int64(v))
            if u < 0x28 { out = [UInt8(u) + 8] }
            else if u <= 0xFF { out = [0x30] + Self.little(u, 1) }
            else if u <= 0xFFFF { out = [0x31] + Self.little(u, 2) }
            else if u <= 0xFFFF_FFFF { out = [0x32] + Self.little(u, 4) }
            else { out = [0x33] + Self.little(u, 8) }
        case let .double(v): out = [0x36] + Self.little(v.bitPattern, 8)
        case let .string(v):
            out = Self.sized(Array(v.utf8), short: 0x40, long: 0x61, widths: [1, 2, 3, 4])
        case let .data(v):
            out = Self.sized(v, short: 0x70, long: 0x91, widths: [1, 2, 4, 8])
        case let .array(items):
            out = [0xD0 + UInt8(min(items.count, 0xF))]
            for item in items { out += item.encode(&seen) }
            if items.count >= 0xF { out.append(0x03) }
        case let .dict(pairs):
            out = [0xE0 + UInt8(min(pairs.count, 0xF))]
            for (k, v) in pairs { out += k.encode(&seen) + v.encode(&seen) }
            if pairs.count >= 0xF { out.append(0x03) }
        }

        if let index = seen.firstIndex(of: out) {
            if index < 0x21 { return [0xA0 + UInt8(index)] }
            let u = UInt64(index)
            if u <= 0xFF { return [0xC1] + Self.little(u, 1) }
            if u <= 0xFFFF { return [0xC2] + Self.little(u, 2) }
            if u <= 0xFFFF_FFFF { return [0xC3] + Self.little(u, 4) }
            return [0xC4] + Self.little(u, 8)
        }
        if out.count > 1 { seen.append(out) }
        return out
    }

    /// Short values carry their length in the tag; longer ones in the first
    /// little-endian width that fits, with the tag saying which.
    private static func sized(_ bytes: [UInt8], short: UInt8, long: UInt8, widths: [Int]) -> [UInt8] {
        let n = UInt64(bytes.count)
        if n <= 0x20 { return [short + UInt8(n)] + bytes }
        for (i, width) in widths.enumerated() where width == 8 || n < 1 << (8 * UInt64(width)) {
            return [long + UInt8(i)] + little(n, width) + bytes
        }
        return []
    }

    private static func little(_ v: UInt64, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) }
    }

    // MARK: - Decoding

    static func decode(_ bytes: [UInt8]) throws -> OPACK {
        var seen: [OPACK] = []
        var i = 0
        return try decode(bytes, &i, &seen)
    }

    private static func decode(_ b: [UInt8], _ i: inout Int, _ seen: inout [OPACK]) throws -> OPACK {
        func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, i + n <= b.count else { throw DecodeError() }
            defer { i += n }
            return Array(b[i..<(i + n)])
        }
        func uint(_ n: Int) throws -> UInt64 {
            try take(n).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        }

        /// A count of 0xF means "until a 0x03 terminator".
        func done(_ n: Int, _ count: UInt8) throws -> Bool {
            guard count == 0xF else { return n == Int(count) }
            guard i < b.count else { throw DecodeError() }
            if b[i] == 0x03 { i += 1; return true }
            return false
        }

        let tag = try take(1)[0]
        var value: OPACK
        var remember = true
        switch tag {
        case 0x01: value = .bool(true); remember = false
        case 0x02: value = .bool(false); remember = false
        case 0x04: value = .null; remember = false
        case 0x05:
            let raw = try take(16)
            value = .uuid(UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                                      raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15])))
        case 0x06: value = .int(Int(truncatingIfNeeded: try uint(8))) // absolute time, as pyatv reads it
        case 0x08...0x2F: value = .int(Int(tag) - 8); remember = false
        case 0x30...0x33: value = .int(Int(truncatingIfNeeded: try uint(1 << Int(tag & 0xF))))
        case 0x35: value = .double(Double(Float(bitPattern: UInt32(try uint(4)))))
        case 0x36: value = .double(Double(bitPattern: try uint(8)))
        case 0x40...0x60: value = try string(take(Int(tag) - 0x40))
        case 0x61...0x64: value = try string(take(Int(try uint(Int(tag & 0xF)))))
        case 0x70...0x90: value = .data(try take(Int(tag) - 0x70))
        case 0x91...0x94: value = .data(try take(Int(try uint(1 << (Int(tag & 0xF) - 1)))))
        case 0xA0...0xC0:
            guard Int(tag - 0xA0) < seen.count else { throw DecodeError() }
            value = seen[Int(tag - 0xA0)]
        case 0xC1...0xC4:
            let index = Int(try uint(Int(tag - 0xC0)))
            guard index < seen.count else { throw DecodeError() }
            value = seen[index]
        case 0xD0...0xDF:
            var items: [OPACK] = []
            while try !done(items.count, tag & 0xF) { items.append(try decode(b, &i, &seen)) }
            value = .array(items)
            remember = false
        case 0xE0...0xEF:
            var pairs: [(OPACK, OPACK)] = []
            while try !done(pairs.count, tag & 0xF) {
                let key = try decode(b, &i, &seen)
                pairs.append((key, try decode(b, &i, &seen)))
            }
            value = .dict(pairs)
            remember = false
        default: throw DecodeError()
        }
        if remember, !seen.contains(value) { seen.append(value) }
        return value
    }

    private static func string(_ bytes: [UInt8]) throws -> OPACK {
        guard let s = String(bytes: bytes, encoding: .utf8) else { throw DecodeError() }
        return .string(s)
    }
}

extension OPACK: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(arrayLiteral elements: OPACK...) { self = .array(elements) }
    init(dictionaryLiteral elements: (OPACK, OPACK)...) { self = .dict(elements) }
}
