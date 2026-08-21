import Foundation
import Testing
@testable import Modules

@Suite("UDPCodec")
struct UDPCodecTests {
    @Test("encodes a utf8 string and a byte array")
    func encode() {
        #expect(UDPCodec.encode("hi") == Data("hi".utf8))
        #expect(UDPCodec.encode([1, 99, 0, 255]) == Data([1, 99, 0, 255]))
        #expect(UDPCodec.encode([-1]) == nil)
    }

    @Test("decodes utf8 text or base64 binary")
    func decode() {
        #expect(UDPCodec.decode(Data("hello".utf8)) == "hello")
        #expect(UDPCodec.decode(Data([0xFF, 0x00])) == Data([0xFF, 0x00]).base64EncodedString())
        #expect(UDPCodec.decode(Data()) == "")
    }
}
