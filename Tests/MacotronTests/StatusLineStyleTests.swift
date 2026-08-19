import AppKit
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

    @Test("status title uses one native attributed string")
    func attributedTitle() {
        let title = StatusLineStyle.attributedTitle(
            title: "CPU 42%",
            subtitle: "GPU 7%",
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: true
        )
        #expect(title.string == "CPU 42%\nGPU 7%")
        #expect(title.attribute(.font, at: 7, effectiveRange: nil) != nil)
        let titleParagraph = title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let subtitleParagraph = title.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as? NSParagraphStyle
        #expect(titleParagraph?.maximumLineHeight == 10.5)
        #expect(subtitleParagraph?.maximumLineHeight == 10)
    }

    @Test("two capped lines fit inside the menu bar button")
    func lineHeightsFit() {
        let standard = StatusLineStyle.maximumLineHeight(secondary: false, subtitle: false)
            + StatusLineStyle.maximumLineHeight(secondary: false, subtitle: true)
        let secondary = StatusLineStyle.maximumLineHeight(secondary: true, subtitle: false)
            + StatusLineStyle.maximumLineHeight(secondary: true, subtitle: true)
        #expect(standard < 22)
        #expect(secondary < 22)
    }

    @Test("minimum width remains a floor")
    func minimumWidth() {
        #expect(StatusLineStyle.length(naturalWidth: 120, minWidth: 96) == 120)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: 96) == 96)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: nil) == nil)
    }
}
