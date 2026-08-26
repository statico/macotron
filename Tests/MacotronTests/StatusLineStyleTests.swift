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

    @Test("icon centres on the text, not the bar")
    func iconFollowsTheText() {
        let lines = StatusLineStyle.lines(
            title: "Ian / Tom",
            subtitle: "12:30 PM",
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: true
        )
        let heights = lines.map { $0.size().height }
        let origins = StatusLineStyle.lineOrigins(barHeight: 24, heights: heights)
        let center = StatusLineStyle.textCenter(lines: lines, origins: origins, height: 24)
        // Line boxes hang lower than their ink, so the optical centre of the
        // stack sits below the middle of the bar.
        #expect(center < 12)
        #expect(center > 9)
        #expect(StatusLineStyle.textCenter(lines: [], origins: [], height: 24) == 12)
    }

    @Test("minimum width remains a floor")
    func minimumWidth() {
        #expect(StatusLineStyle.length(naturalWidth: 120, minWidth: 96) == 120)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: 96) == 96)
        #expect(StatusLineStyle.length(naturalWidth: 80, minWidth: nil) == 80)
    }

    @Test("icon uses ink bounds instead of the SF Symbol canvas")
    @MainActor
    func iconUsesInkBounds() {
        let lines = StatusLineStyle.lines(
            title: "CPU 100%",
            subtitle: "GPU 100%",
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: true
        )
        let icon = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        guard let icon else {
            Issue.record("missing cpu symbol")
            return
        }
        let textWidth = lines.map { $0.size().width }.max() ?? 0
        let image = StatusLineStyle.image(icon: icon, lines: lines, height: 30)
        let canvasLayout = icon.size.width + 4 + textWidth
        #expect(image.size.width < canvasLayout)
        let ink = StatusLineStyle.inkFrame(icon)
        #expect(abs(image.size.width - (ink.width + StatusLineStyle.iconTextSpacing + textWidth)) < 1)
    }

    @Test("single line with icon composes a usable image")
    @MainActor
    func singleLineComposedImage() {
        let lines = StatusLineStyle.lines(
            title: "C-Media USB Headphone Set",
            subtitle: nil,
            color: nil,
            subtitleColor: nil,
            bold: false,
            italic: false,
            secondary: false
        )
        #expect(lines.count == 1)
        print("line size:", lines[0].size())
        let icon = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        print("icon size:", icon?.size ?? .zero)
        let image = StatusLineStyle.image(icon: icon, lines: lines, height: 30)
        print("composed size:", image.size)
        #expect(image.size.width > 100)
        #expect(image.size.height == 30)
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
