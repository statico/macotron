// PanelShellTests.swift — JSON-encode CSS for the panel user script
import AppKit
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
        #expect(glass.contains("html { color-scheme: light dark; background: transparent"))
        #expect(glass.contains("background: transparent"))
        #expect(!glass.contains("background: light-dark(#f5f5f7"))
        let opaque = PanelShell.css(glass: false)
        #expect(opaque.contains("background: light-dark(#f5f5f7"))
        #expect(!opaque.contains("background: transparent"))
    }

    @Test("host CSS exposes system color variables")
    func systemColorVariables() {
        let css = PanelShell.css(glass: false)
        #expect(css.contains("--macotron-accent: AccentColor"))
        #expect(css.contains("--macotron-control: ButtonFace"))
        #expect(css.contains("button.primary"))
        #expect(css.contains(".toolbar textarea"))
        #expect(css.contains("min-height: 52px"))
    }

    @Test("glass parses true, regular, translucent, and clear")
    func glassParse() {
        #expect(PanelGlass.parse(true) == .regular)
        #expect(PanelGlass.parse(false) == .none)
        #expect(PanelGlass.parse("regular") == .regular)
        #expect(PanelGlass.parse("translucent") == .translucent)
        #expect(PanelGlass.parse("clear") == .clear)
        #expect(PanelGlass.parse("none") == .none)
    }

    @Test("frameless panels drop the title bar")
    func framelessStyleMask() {
        #expect(PanelChrome.styleMask(frameless: true).contains(.nonactivatingPanel))
        #expect(PanelChrome.styleMask(frameless: false).contains(.nonactivatingPanel))
        #expect(PanelChrome.styleMask(frameless: true).contains(.fullSizeContentView))
        #expect(!PanelChrome.styleMask(frameless: true).contains(.titled))
        #expect(PanelChrome.styleMask(frameless: false).contains(.titled))
        #expect(!PanelChrome.styleMask(frameless: false).contains(.fullSizeContentView))
    }

    @Test("jsonString quotes and escapes a Swift string")
    func jsonStringEscapesQuotes() {
        #expect(PanelShell.jsonString("a\"b") == "\"a\\\"b\"")
        #expect(PanelShell.jsonString("line\n") == "\"line\\n\"")
    }
}

@Suite("PanelHost")
@MainActor
struct PanelHostDeliveryTests {
    /// Collects what the page posts back, so the test can tell "delivered late"
    /// from "never delivered".
    private final class Inbox { var messages: [String] = [] }

    @Test("a message posted before the page loads is delivered once it does")
    func queuesUntilPageLoads() async throws {
        let inbox = Inbox()
        let host = PanelHost(
            id: "queue-test",
            title: "Queue",
            width: 200,
            height: 200,
            html: "<script>window.__macotronReceive=(d)=>"
                + "window.webkit.messageHandlers.macotron.postMessage(String(d && d.hello));</script>",
            hostChrome: false,
            onMessage: { _, body in inbox.messages.append(body as? String ?? "") },
            onClosed: {}
        )
        defer { host.close() }
        host.show()
        // Straight after open, which is when a plugin seeds its panel: the page
        // has not parsed its script yet, so this has to wait for it.
        host.evaluateJSON(["hello": "world"])

        for _ in 0..<100 where inbox.messages.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(inbox.messages == ["world"])
    }
}
