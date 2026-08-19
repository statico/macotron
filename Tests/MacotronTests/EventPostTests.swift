import CoreGraphics
import Testing
@testable import Modules

@Suite("EventPost")
struct EventPostTests {
    @Test("modifier names map to CGEventFlags")
    func modifiers() {
        let flags = EventPost.modifierFlags(["cmd", "shift", "OPT", "fn"])
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskShift))
        #expect(flags.contains(.maskAlternate))
        #expect(flags.contains(.maskSecondaryFn))
        #expect(!flags.contains(.maskControl))
        #expect(EventPost.flagNames(flags) == ["cmd", "shift", "opt", "fn"])
    }

    @Test("mouse button aliases")
    func buttons() {
        #expect(EventPost.mouseButton("left") == .left)
        #expect(EventPost.mouseButton("right") == .right)
        #expect(EventPost.mouseButton("middle") == .center)
        #expect(EventPost.mouseButton("center") == .center)
        #expect(EventPost.mouseButton("nope") == .left)
    }

    @Test("tap type names")
    func tapTypes() {
        #expect(EventPost.tapMask(for: "flagsChanged") == 1 << CGEventType.flagsChanged.rawValue)
        #expect(EventPost.tapMask(for: "scroll") == 1 << CGEventType.scrollWheel.rawValue)
        #expect(EventPost.tapMask(for: "scrollWheel") == 1 << CGEventType.scrollWheel.rawValue)
        #expect(EventPost.tapMask(for: "rightMouseDown") == 1 << CGEventType.rightMouseDown.rawValue)
        #expect(EventPost.tapMask(for: "nope") == nil)
        #expect(EventPost.typeName(.flagsChanged) == "flagsChanged")
        #expect(EventPost.typeName(.scrollWheel) == "scroll")
    }
}

@Suite("DisplayChange")
struct DisplayChangeTests {
    @Test("named flags skip beginConfiguration")
    func names() {
        #expect(DisplayChange.names(.beginConfigurationFlag) == [])
        #expect(DisplayChange.shouldEmit(.beginConfigurationFlag) == false)
        let flags: CGDisplayChangeSummaryFlags = [.addFlag, .mirrorFlag, .beginConfigurationFlag]
        #expect(DisplayChange.names(flags) == ["add", "mirror"])
        #expect(DisplayChange.shouldEmit(flags) == true)
        #expect(DisplayChange.names([.movedFlag, .desktopShapeChangedFlag]) == ["move", "shape"])
        #expect(DisplayChange.names([.setMainFlag, .setModeFlag, .unMirrorFlag]) == ["main", "mode", "unmirror"])
    }
}
