import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("FileSearch")
struct FileSearchTests {
    private static let mock = #"""
        var html = "";
        var opened = null;
        var macotron = {
            plugin: () => ({}),
            command: (n, d, fn) => { fn(); },
            panel: {
                open: (opts) => { opened = opts; html = opts.html; return "panel"; },
                onMessage: () => {},
                postMessage: () => {},
                close: () => {}
            },
            spotlight: { search: async () => [] },
            shell: { run: async () => ({}) },
            notify: { toast: () => {} }
        };
        """#

    private func eval(_ js: String) throws -> String {
        try PluginHarness.eval(plugin: "file-search.js", mock: Self.mock, extra: js)
    }

    @Test("ctrl-p and up move to the previous row")
    func navUp() throws {
        let result = try eval(#"JSON.stringify([navDelta("ArrowUp", false), navDelta("p", true), navDelta("P", true)])"#)
        #expect(result == "[-1,-1,-1]")
    }

    @Test("down, ctrl-n, and ctrl-m move to the next row")
    func navDown() throws {
        let result = try eval(#"JSON.stringify([navDelta("ArrowDown", false), navDelta("n", true), navDelta("m", true)])"#)
        #expect(result == "[1,1,1]")
    }

    @Test("selection stays in range")
    func clamp() throws {
        let result = try eval("JSON.stringify([clampIndex(-1, 3), clampIndex(1, 3), clampIndex(9, 3), clampIndex(0, 0)])")
        #expect(result == "[0,1,2,0]")
    }

    @Test("panel html has a hover style")
    func hover() throws {
        let html = try eval("html")
        #expect(html.contains(":hover") || html.contains("onmouseover"))
    }

    @Test("opens frameless translucent and closes when unfocused")
    func framelessTranslucent() throws {
        let result = try eval(#"JSON.stringify({ frameless: opened.frameless, glass: opened.glass, closeOnBlur: opened.closeOnBlur, mono: html.indexOf("mono") !== -1 })"#)
        #expect(result.contains(#""frameless":true"#))
        #expect(result.contains(#""glass":"translucent""#))
        #expect(result.contains(#""closeOnBlur":true"#))
        #expect(result.contains(#""mono":false"#))
    }

    @Test("shows a spinner while searching")
    func spinner() throws {
        let html = try eval("html")
        #expect(html.contains("spinner"))
        #expect(html.contains("@keyframes"))
        #expect(html.contains("Searching"))
    }

    @Test("kind select is posted with search")
    func kindSelect() throws {
        let html = try eval("html")
        #expect(html.contains("id=\"kind\""))
        #expect(html.contains("pdf"))
        #expect(html.contains("kind:"))
        #expect(html.contains("metaKey"))
    }
}
