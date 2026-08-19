import Testing
@testable import MacotronUI

@Suite("StatusLineStyle")
struct StatusLineStyleTests {
    @Test("two lines match unless secondary is on")
    func equalByDefault() {
        #expect(StatusLineStyle.fontSize(twoLine: true, secondary: false, subtitle: false) == 10)
        #expect(StatusLineStyle.fontSize(twoLine: true, secondary: false, subtitle: true) == 10)
        #expect(StatusLineStyle.fontSize(twoLine: true, secondary: true, subtitle: false) == 10)
        #expect(StatusLineStyle.fontSize(twoLine: true, secondary: true, subtitle: true) == 9)
        #expect(StatusLineStyle.fontSize(twoLine: false, secondary: false, subtitle: false) == 13)
    }
}
