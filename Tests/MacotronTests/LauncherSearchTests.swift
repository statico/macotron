import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("LauncherSearch")
struct LauncherSearchTests {
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
        let engine = Engine()
        // A plugin that paints from a promise only settles once evaluate()
        // drains the job queue, so `extra` has to run after that, not with it.
        let (_, error) = engine.evaluate("\(mock)\n\(source)", filename: url.path)
        #expect(error == nil)
        let (result, extraError) = engine.evaluate(extra, filename: url.path)
        #expect(extraError == nil)
        return result ?? ""
    }

    @Test("contacts email and phone clicks open mailto and tel")
    func contactsOpen() throws {
        let result = try eval(plugin: "contacts.js", mock: #"""
            var opened = [];
            var items = [];
            var macotron = {
                plugin: () => ({}),
                every: () => {},
                contacts: { list: () => Promise.resolve([
                    { id: "1", name: "Ada", emails: ["ada@example.com"], phones: [], organization: "" },
                    { id: "2", name: "Bob", emails: [], phones: ["555-0100"], organization: "Acme" }
                ]) },
                launcher: { set: (_, rows) => { items = rows; } },
                url: { open: (url) => { opened.push(url); } },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            items[0].onClick();
            items[1].onClick();
            JSON.stringify(opened)
            """#)
        #expect(result.contains("mailto:ada@example.com"))
        #expect(result.contains("tel:555-0100"))
    }

    @Test("Search Google opens a google URL with the query")
    func searchGoogle() throws {
        let result = try eval(plugin: "web-search.js", mock: #"""
            var opened = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                url: { open: (url) => { opened.push(url); } },
                shell: { run: () => {} },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            commands["Search Google"]({ q: "macotron" });
            JSON.stringify(opened)
            """#)
        #expect(result.contains("google"))
        #expect(result.contains("macotron"))
    }

    @Test("Define opens dict:// for the word")
    func define() throws {
        let result = try eval(plugin: "web-search.js", mock: #"""
            var runs = [];
            var commands = {};
            var macotron = {
                plugin: () => ({}),
                command: (name, desc, fn) => { commands[name] = fn; },
                url: { open: () => {} },
                shell: { run: (cmd, args) => { runs.push({ cmd: cmd, args: args }); } },
                notify: { toast: () => {} }
            };
            """#, extra: #"""
            commands["Define"]({ q: "apple" });
            JSON.stringify(runs)
            """#)
        #expect(result.contains("dict://"))
        #expect(result.contains("apple"))
    }
}
