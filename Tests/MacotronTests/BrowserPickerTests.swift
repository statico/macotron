import Foundation
import Testing
@testable import MacotronEngine

/// Drives `browser-picker.js` through the `url.on` handler it registers and
/// reads back what it handed to `url.open`.
@MainActor
@Suite("BrowserPicker")
struct BrowserPickerTests {
    /// Two profiles share the name "Work" on purpose.
    static let localState = #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"},"Profile 2":{"name":"Work"},"Profile 3":{"name":"Side"}}}}"#

    static func load(_ rules: String, unmatched: String = "ask", blocked: Bool = false) throws -> Engine {
        try PluginHarness.load(plugin: "browser-picker.js", mock: """
            var __handlers = {}, __opened = [], __checks = [], __panels = 0, __blocked = \(blocked);
            var macotron = {
                plugin: () => ({ defaultBrowser: \(js(unmatched)), rules: \(js(rules)) }),
                url: {
                    setDefaultHandler: () => true,
                    on: (scheme, host, cb) => { __handlers[scheme + ":" + host] = cb; },
                    open: (url, id, profile) => { __opened.push(profile === undefined ? id : id + "|" + profile); return true; },
                },
                fs: {
                    exists: (p) => ["Default", "Profile 1", "Profile 2", "Profile 3"]
                        .some((f) => p === "~/Library/Application Support/Google/Chrome/" + f),
                    read: (p) => {
                        if (__blocked) throw new Error("Operation not permitted");
                        if (p === "~/Library/Application Support/Google/Chrome/Local State") return \(js(localState));
                        throw new Error("missing " + p);
                    },
                },
                checks: (rows) => { __checks = rows; },
                panel: { open: () => { __panels++; return "p"; }, onMessage: () => {}, close: () => {} },
                command: () => {},
                log: () => {},
                notify: { toast: () => {} },
            };
            // Where one link went: "bundleID", "bundleID|profile", or "ask".
            function __go(url, sourceBundle) {
                const m = url.match(/^(\\w+):\\/\\/([^/?#]+)([^?#]*)/);
                __opened = []; __panels = 0;
                __handlers[m[1] + ":*"]({ url, scheme: m[1], host: m[2], path: m[3] || "/", sourceBundle });
                return __opened[0] || (__panels ? "ask" : "nothing");
            }
            """)
    }

    static func go(_ engine: Engine, _ url: String, from: String? = nil) -> String {
        PluginHarness.run(engine, "__go(\(js(url)), \(from.map(js) ?? "undefined"))")
    }

    static let chrome = "com.google.Chrome"
    static let safari = "com.apple.Safari"

    @Test("a host matches its subdomains but not a longer name")
    func hostBoundary() throws {
        let e = try Self.load("example.com safari")
        #expect(Self.go(e, "https://www.example.com/") == Self.safari)
        #expect(Self.go(e, "https://EXAMPLE.com/") == Self.safari)
        #expect(Self.go(e, "https://badexample.com/") == "ask")
    }

    @Test("a path prefix ignores case and stops at segment boundaries")
    func pathPrefix() throws {
        let e = try Self.load("github.com/acme chrome")
        #expect(Self.go(e, "https://github.com/acme") == Self.chrome)
        #expect(Self.go(e, "https://github.com/Acme/repo") == Self.chrome)
        #expect(Self.go(e, "https://github.com/acme-evil") == "ask")
        #expect(Self.go(e, "https://github.com/other") == "ask")
    }

    @Test("from: matches only links from that app")
    func fromApp() throws {
        let e = try Self.load("from:com.tinyspeck.slackmacgap * chrome\nexample.com from:com.apple.mail safari")
        #expect(Self.go(e, "https://x.com/", from: "com.tinyspeck.slackmacgap") == Self.chrome)
        #expect(Self.go(e, "https://x.com/") == "ask")
        #expect(Self.go(e, "https://example.com/", from: "com.apple.mail") == Self.safari)
        #expect(Self.go(e, "https://example.com/", from: "com.apple.Notes") == "ask")
    }

    @Test("a profile with a space reaches url.open whole")
    func profileWithSpace() throws {
        let e = try Self.load("youtube.com chrome:Default\n* chrome:Profile 1")
        #expect(Self.go(e, "https://www.youtube.com/watch") == "\(Self.chrome)|Default")
        #expect(Self.go(e, "https://example.com/") == "\(Self.chrome)|Profile 1")
    }

    @Test("a unique display name resolves to its folder")
    func displayName() throws {
        let e = try Self.load("* chrome:side")
        #expect(Self.go(e, "https://example.com/") == "\(Self.chrome)|Profile 3")
    }

    @Test("a shared or unknown display name opens without a profile and reports a check")
    func ambiguousName() throws {
        for rules in ["* chrome:Work", "* chrome:Nobody"] {
            let e = try Self.load(rules)
            #expect(Self.go(e, "https://example.com/") == Self.chrome)
            #expect(PluginHarness.run(e, "__checks[0].ok") == "false")
        }
    }

    @Test("a profile on a non-Chromium browser is dropped and reported")
    func profileOnSafari() throws {
        let e = try Self.load("* safari:Work")
        #expect(Self.go(e, "https://example.com/") == Self.safari)
        #expect(PluginHarness.run(e, "__checks[0].ok") == "false")
    }

    @Test("a browser name ignores case and spaces")
    func browserNames() throws {
        let e = try Self.load("youtube.com Chrome Beta\nyoutu.be chromebeta\nnotion.so Safari")
        #expect(Self.go(e, "https://youtube.com/") == "com.google.Chrome.beta")
        #expect(Self.go(e, "https://youtu.be/") == "com.google.Chrome.beta")
        #expect(Self.go(e, "https://notion.so/") == Self.safari)
        #expect(PluginHarness.run(e, "__checks[0].ok") == "true")
    }

    @Test("a folder name works when macOS blocks the profile list")
    func folderWithoutLocalState() throws {
        let e = try Self.load("youtube.com chrome:Profile 1\nexample.com chrome:Profile 9", blocked: true)
        #expect(Self.go(e, "https://youtube.com/") == Self.chrome + "|Profile 1")
        #expect(Self.go(e, "https://example.com/") == Self.chrome)
        #expect(PluginHarness.run(e, "__checks[0].ok") == "false")
    }

    @Test("the first matching line wins")
    func firstMatch() throws {
        let e = try Self.load("* safari\nyoutube.com chrome")
        #expect(Self.go(e, "https://youtube.com/") == Self.safari)
    }

    @Test("with no match, the Unmatched links setting decides")
    func unmatched() throws {
        #expect(Self.go(try Self.load("youtube.com chrome"), "https://example.com/") == "ask")
        #expect(Self.go(try Self.load("youtube.com chrome", unmatched: "firefox"), "https://example.com/") == "org.mozilla.firefox")
    }

    @Test("the default rules and a regex rule route as before")
    func legacyRules() throws {
        let e = try Self.load("youtube.com safari\nyoutu.be safari\n/^github\\./i firefox\ndocs.google.com com.brave.Browser")
        #expect(PluginHarness.run(e, "__checks[0].ok") == "true")
        #expect(Self.go(e, "https://youtu.be/abc") == Self.safari)
        #expect(Self.go(e, "https://GitHub.com/x") == "org.mozilla.firefox")
        #expect(Self.go(e, "https://docs.google.com/d") == "com.brave.Browser")
    }

    @Test("bad rules are skipped and reported, and their links still open")
    func badRules() throws {
        let e = try Self.load("/[/ chrome\nexample.com nosuchbrowser\nlonely")
        #expect(PluginHarness.run(e, "__checks.length") == "3")
        #expect(Self.go(e, "https://example.com/") == "ask")
    }
}

private func js(_ string: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed), encoding: .utf8)!
}
