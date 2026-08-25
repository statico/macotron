import AppKit
import Testing
@testable import MacotronUI

@MainActor
@Suite("LauncherPanel")
struct LauncherPanelTests {
    @Test("is a nonactivating floating panel so it does not activate Macotron")
    func nonactivating() {
        let panel = LauncherPanel(contentView: NSView(frame: .zero), windowFrame: LauncherFrame())
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeMain)
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.level == .floating)
        #expect(panel.isFloatingPanel)
    }

    /// Layer corner masking alone leaves the window shadow square, which shows up
    /// as unshadowed notches in the corners over flat, light windows.
    @Test("translucent chrome shapes its vibrancy with a resizable rounded mask")
    func translucentCornerMask() throws {
        let panel = LauncherPanel(contentView: NSView(frame: .zero), windowFrame: LauncherFrame())
        panel.applyBackground(.translucent)
        let visual = try #require(panel.contentView as? NSVisualEffectView)
        #expect(visual.blendingMode == .behindWindow)

        let mask = try #require(visual.maskImage)
        #expect(mask.resizingMode == .stretch)
        #expect(mask.capInsets.left > 0)
        #expect(mask.capInsets.left == mask.capInsets.right)
        #expect(mask.capInsets.top == mask.capInsets.bottom)

        let rep = try #require(NSBitmapImageRep(data: mask.tiffRepresentation ?? Data()))
        let corner = try #require(rep.colorAt(x: 0, y: 0))
        let center = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        #expect(corner.alphaComponent < 0.5)
        #expect(center.alphaComponent > 0.5)
    }
}

@MainActor
@Suite("LauncherSearchDebounce")
struct LauncherSearchDebounceTests {
    @Test("opening the launcher and the first letter after it search at once")
    func firstKeystrokeIsInstant() {
        #expect(LauncherView.searchDelay(query: "", applied: "") == nil)
        #expect(LauncherView.searchDelay(query: "s", applied: "") == nil)
    }

    @Test("further typing waits")
    func typingWaits() {
        #expect(LauncherView.searchDelay(query: "sa", applied: "s") == .milliseconds(80))
        #expect(LauncherView.searchDelay(query: "", applied: "s") == .milliseconds(80))
    }

    @Test("a refresh of the query already on screen does not wait")
    func refreshIsInstant() {
        #expect(LauncherView.searchDelay(query: "safari", applied: "safari") == nil)
    }
}
