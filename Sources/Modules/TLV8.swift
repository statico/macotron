import Foundation

/// HomeKit's TLV8: one tag byte, one length byte, then the value. A value
/// longer than 255 bytes is split into consecutive items with the same tag.
enum TLV8 {
    enum Tag: UInt8 {
        case method = 0x00
        case identifier = 0x01
        case salt = 0x02
        case publicKey = 0x03
        case proof = 0x04
        case encryptedData = 0x05
        case state = 0x06
        case error = 0x07
        case backOff = 0x08
        case signature = 0x0A
        case name = 0x11
    }

    static func encode(_ items: [(UInt8, [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        for (tag, value) in items {
            var rest = value[...]
            repeat {
                let chunk = rest.prefix(255)
                out += [tag, UInt8(chunk.count)] + chunk
                rest = rest.dropFirst(chunk.count)
            } while !rest.isEmpty
        }
        return out
    }

    static func encode(_ items: [(Tag, [UInt8])]) -> [UInt8] {
        encode(items.map { ($0.0.rawValue, $0.1) })
    }

    /// Returns nil for a truncated item. Fragments of one tag are joined.
    static func decode(_ bytes: [UInt8]) -> [UInt8: [UInt8]]? {
        var out: [UInt8: [UInt8]] = [:]
        var i = 0
        while i < bytes.count {
            guard i + 1 < bytes.count else { return nil }
            let tag = bytes[i]
            let length = Int(bytes[i + 1])
            guard i + 2 + length <= bytes.count else { return nil }
            out[tag, default: []] += bytes[(i + 2)..<(i + 2 + length)]
            i += 2 + length
        }
        return out
    }
}
