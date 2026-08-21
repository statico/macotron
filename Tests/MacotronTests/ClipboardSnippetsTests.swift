import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("ClipboardSnippets")
struct ClipboardSnippetsTests {
    private func pluginURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/\(name)")
    }

    private func eval(plugin: String, mock: String, extra: String) throws -> String {
        let url = pluginURL(plugin)
        let source = try String(contentsOf: url, encoding: .utf8)
        let harness = """
            \(mock)
            \(source)
            \(extra)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: url.path)
        #expect(error == nil)
        return result ?? ""
    }

    @Test("snippets launcher includes omw and insert calls insert")
    func snippetsOmw() throws {
        let result = try eval(plugin: "snippets.js", mock: #"""
            var rows = [];
            var inserts = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                launcher: { set: (id, r) => { rows = r; } },
                snippets: {
                    set: () => {},
                    setExpansionEnabled: () => {},
                    insert: (abbr) => { inserts.push(abbr); }
                },
                clipboard: { set: () => {} },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            var omw = rows.find((r) => r.id === "omw" || r.title === "omw");
            omw.onClick();
            JSON.stringify({ titles: rows.map((r) => r.title), inserts: inserts, hasInsert: !!commands["Insert OMW"] })
            """#)
        #expect(result.contains("omw"))
        #expect(result.contains(#""inserts":["omw"]"#))
        #expect(result.contains(#""hasInsert":true"#))
    }

    @Test("clipboard rowsFromHistory titles images as Image")
    func clipboardRows() throws {
        let result = try eval(plugin: "clipboard-history.js", mock: #"""
            var macotron = {
                plugin: () => ({}),
                command: () => {},
                on: () => {},
                launcher: { set: () => {} },
                clipboard: { history: () => [] }
            };
            """#, extra: #"""
            JSON.stringify(rowsFromHistory([
                { id: "t", text: "hello", kind: "text", ts: 0 },
                { id: "i", kind: "image", ts: 1 }
            ]).map((r) => ({ id: r.id, title: r.title })))
            """#)
        #expect(result.contains(#""id":"t"#))
        #expect(result.contains(#""title":"hello"#))
        #expect(result.contains(#""id":"i"#))
        #expect(result.contains(#""title":"Image"#))
    }

    @Test("Clipboard History opens a panel and paste closes it")
    func clipboardPanelPaste() throws {
        let result = try eval(plugin: "clipboard-history.js", mock: #"""
            var opened = null;
            var onMessage = null;
            var pasted = [];
            var closed = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                on: () => {},
                launcher: { set: () => {} },
                clipboard: {
                    history: () => [{ id: "t1", text: "hello", kind: "text", ts: 0 }],
                    paste: (id) => { pasted.push(id); }
                },
                panel: {
                    open: (opts) => { opened = opts; return "p1"; },
                    postMessage: () => {},
                    onMessage: (id, fn) => { onMessage = fn; },
                    close: (id) => { closed.push(id); }
                }
            };
            """#, extra: #"""
            commands["Clipboard History"]();
            onMessage({ id: "t1" });
            JSON.stringify({
                glass: opened.glass,
                frameless: opened.frameless,
                closeOnBlur: opened.closeOnBlur,
                width: opened.width,
                height: opened.height,
                pasted: pasted,
                closed: closed
            })
            """#)
        #expect(result.contains(#""glass":"translucent"#))
        #expect(result.contains(#""frameless":true"#))
        #expect(result.contains(#""closeOnBlur":true"#))
        #expect(result.contains(#""width":520"#))
        #expect(result.contains(#""height":420"#))
        #expect(result.contains(#""pasted":["t1"]"#))
        #expect(result.contains(#""closed":["p1"]"#))
    }
}
