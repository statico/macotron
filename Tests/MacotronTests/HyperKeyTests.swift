import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("KeyCombo hyper")
struct KeyComboHyperTests {
    @Test("parse hyper+h is cmd+shift+ctrl+opt+h")
    func parseHyperH() {
        let combo = KeyCombo.parse("hyper+h")
        #expect(combo?.keyCode == CGKeyCode(kVK_ANSI_H))
        #expect(combo?.modifiers == [.maskCommand, .maskShift, .maskControl, .maskAlternate])
    }

    @Test("parse hyper+left is cmd+shift+ctrl+opt+left")
    func parseHyperLeft() {
        let combo = KeyCombo.parse("hyper+left")
        #expect(combo?.keyCode == CGKeyCode(kVK_LeftArrow))
        #expect(combo?.modifiers == [.maskCommand, .maskShift, .maskControl, .maskAlternate])
    }

    @Test("null and invalid still fail parse")
    func invalidStillFails() {
        #expect(KeyCombo.parse("null") == nil)
        #expect(KeyCombo.parse("invalid") == nil)
        #expect(KeyCombo.parse("hyper") == nil)
        #expect(KeyCombo.parse("") == nil)
    }

    @Test("glyphs shows Hyper")
    func hyperGlyphs() {
        let parts = KeyCombo.glyphs("hyper+h")
        #expect(parts.contains(where: { $0 == "Hyper" || $0.contains("Hyper") }))
        #expect(parts.last == "H")
    }
}

@Suite("HyperKey mapper")
struct HyperKeyMapperTests {
    @Test("caps flagsChanged is swallowed and holds")
    func capsHold() {
        var mapper = HyperKeyMapper(kind: .caps)
        #expect(mapper.handle(type: .flagsChanged, keyCode: CGKeyCode(kVK_CapsLock), flags: .maskAlphaShift) == .swallow)
        #expect(mapper.held)
        #expect(mapper.handle(type: .flagsChanged, keyCode: CGKeyCode(kVK_CapsLock), flags: []) == .swallow)
        #expect(!mapper.held)
    }

    @Test("held key events get the four modifiers")
    func modifyWhileHeld() {
        var mapper = HyperKeyMapper(kind: .caps)
        _ = mapper.handle(type: .flagsChanged, keyCode: CGKeyCode(kVK_CapsLock), flags: .maskAlphaShift)
        let decision = mapper.handle(type: .keyDown, keyCode: CGKeyCode(kVK_ANSI_H), flags: [])
        #expect(decision == .modify([.maskCommand, .maskShift, .maskControl, .maskAlternate]))
    }

    @Test("fn uses secondary-fn flag for held")
    func fnHold() {
        var mapper = HyperKeyMapper(kind: .fn)
        #expect(mapper.handle(type: .flagsChanged, keyCode: CGKeyCode(kVK_Function), flags: .maskSecondaryFn) == .swallow)
        #expect(mapper.held)
        #expect(mapper.handle(type: .flagsChanged, keyCode: CGKeyCode(kVK_Function), flags: []) == .swallow)
        #expect(!mapper.held)
    }
}

@MainActor
@Suite("Keyboard hyper key")
struct KeyboardHyperKeyTests {
    @Test("setHyperKey dry-run returns true and does not install a tap")
    func dryRun() {
        let hyper = HyperKey()
        #expect(hyper.set("caps", dryRun: true))
        #expect(hyper.current == "caps")
        #expect(hyper.hasTap == false)
        #expect(hyper.set("fn", dryRun: true))
        #expect(hyper.current == "fn")
        #expect(hyper.hasTap == false)
        #expect(!hyper.set("space", dryRun: true))
        #expect(hyper.set(nil, dryRun: true))
        #expect(hyper.current == nil)
        #expect(hyper.hasTap == false)
    }

    @Test("JS setHyperKey dry-run")
    func jsDryRun() {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(KeyboardModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate("""
            JSON.stringify({
                ok: macotron.keyboard.setHyperKey("caps"),
                current: macotron.keyboard.hyperKey(),
                bad: macotron.keyboard.setHyperKey("space"),
                cleared: macotron.keyboard.setHyperKey(null),
                after: macotron.keyboard.hyperKey()
            })
            """)
        #expect(error == nil)
        #expect(result == #"{"ok":true,"current":"caps","bad":false,"cleared":true,"after":null}"#)
    }
}
