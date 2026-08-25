import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Battery")
struct BatteryTests {
    @Test("click menu lists health, cycles, and settings — not a click-through")
    func menuShowsDetails() throws {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/battery.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var statusConfig = null;
            var macotron = {
                plugin: () => ({}),
                system: {
                    battery: () => ({
                        level: 80,
                        charging: true,
                        charged: false,
                        timeRemaining: -1,
                        timeToFull: 45,
                        source: "ac",
                        health: 96,
                        cycles: 69,
                        watts: 87,
                        lowPowerMode: false
                    })
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                url: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: () => {} }
            };
            \(pluginSource)
            JSON.stringify({
                onClick: typeof statusConfig.onClick,
                menu: statusConfig.menu.map((row) => row === "-" ? "-" : row.title)
            })
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        #expect(result?.contains("\"onClick\":\"undefined\"") == true)
        #expect(result?.contains("Maximum capacity 96%") == true)
        #expect(result?.contains("69 cycles") == true)
        #expect(result?.contains("87W adapter") == true)
        #expect(result?.contains("Battery Settings") == true)
    }

    @Test("low power mode menu item turns it on and toasts")
    func lowPowerModeTurnsOn() throws {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/battery.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var statusConfig = null;
            var setArg = null;
            var toast = null;
            var macotron = {
                plugin: () => ({}),
                system: {
                    battery: () => ({
                        level: 80,
                        charging: false,
                        charged: false,
                        timeRemaining: 120,
                        timeToFull: -1,
                        source: "battery",
                        lowPowerMode: false
                    }),
                    setLowPowerMode: (on) => { setArg = on; return Promise.resolve({ ok: true, lowPowerMode: on }); }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                url: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: (title, body) => { toast = { title: title, body: body }; } }
            };
            \(pluginSource)
            var row = statusConfig.menu.find((item) => item.title && item.title.indexOf("Low Power Mode") === 0);
            var hasClick = typeof row.onClick === "function";
            row.onClick();
            """
        let engine = Engine()
        let (_, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        // setLowPowerMode is a promise now, so the toast lands once the job
        // queue has drained -- which the first evaluate does on its way out.
        let (result, readError) = engine.evaluate("""
            JSON.stringify({ setArg: setArg, toast: toast, hasClick: hasClick })
            """)
        #expect(readError == nil)
        #expect(result?.contains("\"hasClick\":true") == true)
        #expect(result?.contains("\"setArg\":true") == true)
        #expect(result?.contains("\"title\":\"Low Power Mode\"") == true)
        #expect(result?.contains("\"body\":\"On\"") == true)
    }
}
