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

    @Test("two-line status renders one line per string")
    func twoLines() {
        let lines = StatusLineStyle.lines(
            title: "CPU 42%",
            subtitle: "GPU 7%",
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: true
        )
        #expect(lines.map(\.string) == ["CPU 42%", "GPU 7%"])
        let titleFont = lines[0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let subtitleFont = lines[1].attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(titleFont?.pointSize == 10)
        #expect(subtitleFont?.pointSize == 9)
    }

    @Test("single line keeps the large menu bar font")
    func singleLine() {
        let lines = StatusLineStyle.lines(
            title: "42%",
            subtitle: nil,
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: false
        )
        #expect(lines.map(\.string) == ["42%"])
        let font = lines[0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 13)
    }

    @Test("line stack is vertically centered in the bar")
    func centeredOrigins() {
        let origins = StatusLineStyle.lineOrigins(barHeight: 30, heights: [12, 12])
        // Symmetric margins: top gap == bottom gap.
        let topGap = 30 - (origins[0] + 12)
        let bottomGap = origins[1]
        #expect(abs(topGap - bottomGap) < 0.001)
        #expect(origins[0] > origins[1])

        let single = StatusLineStyle.lineOrigins(barHeight: 22, heights: [12])
        #expect(single == [5])
    }

    @Test("oversized stack squeezes the gap instead of clipping")
    func squeezedOrigins() {
        let barHeight: CGFloat = 22
        let heights: [CGFloat] = [11.9, 11.9]
        let origins = StatusLineStyle.lineOrigins(barHeight: barHeight, heights: heights)
        // Top line's box stays inside the bar and the bottom line's box
        // starts at or above the bottom edge.
        #expect(origins[0] + heights[0] <= barHeight + 0.001)
        #expect(origins[1] >= -0.001)
    }

    @Test("minimum width remains a floor")
    func minimumWidth() {
        #expect(StatusLineStyle.length(naturalWidth: 120, minWidth: 96) == 120)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: 96) == 96)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: nil) == nil)
    }

    @Test("composed image spans the bar height")
    @MainActor
    func composedImage() {
        let lines = StatusLineStyle.lines(
            title: "CPU 42%",
            subtitle: "GPU 7%",
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: false
        )
        let image = StatusLineStyle.image(icon: nil, lines: lines, height: 24)
        #expect(image.size.height == 24)
        #expect(image.size.width > 0)
    }
}
