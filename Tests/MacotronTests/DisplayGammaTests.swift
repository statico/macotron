import Testing
@testable import Modules

@Suite("DisplayGamma")
struct DisplayGammaTests {
    @Test("identity tables run 0 to 1")
    func identity() {
        let t = DisplayGamma.tables(black: .black, white: .white)
        #expect(t.r.first == 0)
        #expect(t.g.first == 0)
        #expect(t.b.first == 0)
        #expect(t.r.last == 1)
        #expect(t.g.last == 1)
        #expect(t.b.last == 1)
        #expect(t.r.count == 256)
    }

    @Test("red-only whitepoint crushes green and blue")
    func redOnly() {
        let t = DisplayGamma.tables(
            black: .black,
            white: .init(red: 1, green: 0, blue: 0)
        )
        #expect(t.r.last == 1)
        #expect(t.g.last == 0)
        #expect(t.b.last == 0)
        #expect(abs(t.r[127] - 127 / 255) < 0.01)
        #expect(t.g[127] == 0)
    }

    @Test("values clamp to 0...1")
    func clamp() {
        let t = DisplayGamma.tables(
            black: .init(red: -1, green: 0, blue: 0),
            white: .init(red: 2, green: 0.5, blue: 0)
        )
        #expect(t.r.first == 0)
        #expect(t.r.last == 1)
        #expect(t.g.last == 0.5)
    }
}
