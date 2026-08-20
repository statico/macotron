import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("FileSearchDemoTests")
struct FileSearchDemoTests {
    private func eval(_ js: String) throws -> String {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/demo-file-search.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
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
            \(demo)
            \(js)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        return result ?? ""
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

    @Test("opens frameless glass and uses the system font for paths")
    func framelessSystemFont() throws {
        let result = try eval(#"JSON.stringify({ frameless: opened.frameless, glass: opened.glass, mono: html.indexOf("mono") !== -1 })"#)
        #expect(result.contains("\"frameless\":true"))
        #expect(result.contains("\"glass\":\"clear\""))
        #expect(result.contains("\"mono\":false"))
    }
}
