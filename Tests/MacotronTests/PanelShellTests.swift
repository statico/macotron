// PanelShellTests.swift — JSON-encode CSS for the panel user script
import Testing
@testable import Modules

@Suite("PanelShell")
struct PanelShellTests {
    @Test("userScript JSON-encodes CSS as a JavaScript string")
    @MainActor
    func userScriptEncodesCSSString() {
        let source = PanelShell.userScript().source
        #expect(source.contains("s.textContent="))
        #expect(source.contains("color-scheme"))
        #expect(!source.contains("s.textContent=html"))
    }

    @Test("glass stylesheet uses a transparent page background")
    func glassCSSIsTransparent() {
        let glass = PanelShell.css(glass: true)
        #expect(glass.contains("background: transparent"))
        #expect(!glass.contains("background: light-dark(#f5f5f7"))
        let opaque = PanelShell.css(glass: false)
        #expect(opaque.contains("background: light-dark(#f5f5f7"))
        #expect(!opaque.contains("background: transparent"))
    }

    @Test("glass parses true, regular/translucent, and clear")
    func glassParse() {
        #expect(PanelGlass.parse(true) == .regular)
        #expect(PanelGlass.parse(false) == .none)
        #expect(PanelGlass.parse("regular") == .regular)
        #expect(PanelGlass.parse("translucent") == .regular)
        #expect(PanelGlass.parse("clear") == .clear)
        #expect(PanelGlass.parse("none") == .none)
    }

    @Test("jsonString quotes and escapes a Swift string")
    func jsonStringEscapesQuotes() {
        #expect(PanelShell.jsonString("a\"b") == "\"a\\\"b\"")
        #expect(PanelShell.jsonString("line\n") == "\"line\\n\"")
    }
}
