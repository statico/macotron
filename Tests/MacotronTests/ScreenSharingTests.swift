import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Screen Sharing plugin")
struct ScreenSharingTests {
    /// `__prefs` is what plist.read hands back; the store nested in it is
    /// looked up by its base64 so the test sees the two-step read.
    private static let mock = #"""
        var __prefs = null;
        var __stores = {};
        var __menu = null;
        var __rows = null;
        var __opened = [];
        var __launched = [];
        var macotron = {
            plugin: () => ({}),
            plist: {
                read: (path) => path.endsWith("/com.apple.ScreenSharing.plist") ? __prefs : null,
                parse: (input) => (input && __stores[input.base64]) || null
            },
            fs: { watch: () => () => {} },
            app: { launch: (id) => { __launched.push(id); return true; } },
            url: { open: (url, app) => { __opened.push(url + " " + app); return true; } },
            launcher: { set: (_id, rows) => { __rows = rows; } },
            menubar: { status: (_id, cfg) => { __menu = cfg.menu; } },
            notify: { toast: () => {} }
        };
        """#

    private static let saved = #"""
        __prefs = { connectionsStore: "STORE" };
        __stores.STORE = { connectionDetails: {
            a: { connectionParameters: { networkAddress: { _0: {
                address: "hornet.local", displayName: "hornet", username: "ian",
                displayConfiguration: { displayType: { virtualDisplays: { numberOfDisplays: 1 } } } } } } },
            b: { connectionParameters: { networkAddress: { _0: { address: "10.0.0.2", port: 5901 } } } },
            c: { connectionParameters: {} }
        } };
        """#

    @Test("saved connections become sorted menu rows and launcher rows")
    func lists() throws {
        let engine = try PluginHarness.load(plugin: "screen-sharing.js", mock: Self.mock + Self.saved)
        #expect(PluginHarness.run(engine, "__menu.map(m => m.title || m).join(',')")
            == "10.0.0.2,hornet,-,Open Screen Sharing,Refresh")
        #expect(PluginHarness.run(engine, "__rows.map(r => r.id).join(',')") == "10.0.0.2:5901,hornet.local")
    }

    @Test("a row connects with the saved display type, and Open launches the app")
    func connects() throws {
        let engine = try PluginHarness.load(plugin: "screen-sharing.js", mock: Self.mock + Self.saved)
        PluginHarness.run(engine, "__menu[1].onClick(); __menu[0].onClick(); __menu[3].onClick();")
        #expect(PluginHarness.run(engine, "__opened.join('|')")
            == "vnc://ian@hornet.local?quality=high&numVirtualDisplays=1 com.apple.ScreenSharing"
            + "|vnc://10.0.0.2:5901 com.apple.ScreenSharing")
        #expect(PluginHarness.run(engine, "__launched.join(',')") == "com.apple.ScreenSharing")
    }

    @Test("no prefs reads as no saved connections; a bad store is an error row")
    func missing() throws {
        let none = try PluginHarness.load(plugin: "screen-sharing.js", mock: Self.mock)
        #expect(PluginHarness.run(none, "__menu[0].title") == "No saved connections")

        let bad = try PluginHarness.load(plugin: "screen-sharing.js", mock: Self.mock + "__prefs = { connectionsStore: 'X' };")
        #expect(PluginHarness.run(bad, "__menu[0].title") == "Can't read connections: unreadable connectionsStore")
    }
}
