import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Battery")
struct BatteryTests {
    @Test("click menu lists health, cycles, and settings — not a click-through")
    func menuShowsDetails() throws {
        let result = try PluginHarness.eval(plugin: "battery.js", mock: #"""
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
            """#, extra: #"""
            JSON.stringify({
                onClick: typeof statusConfig.onClick,
                menu: statusConfig.menu.map((row) => row === "-" ? "-" : row.title)
            })
            """#)
        #expect(result.contains("\"onClick\":\"undefined\""))
        #expect(result.contains("Maximum capacity 96%"))
        #expect(result.contains("69 cycles"))
        #expect(result.contains("87W adapter"))
        #expect(result.contains("Battery Settings"))
    }

    @Test("low power mode menu item turns it on and toasts")
    func lowPowerModeTurnsOn() throws {
        let engine = try PluginHarness.load(plugin: "battery.js", mock: #"""
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
            """#, extra: #"""
            var row = statusConfig.menu.find((item) => item.title && item.title.indexOf("Low Power Mode") === 0);
            var hasClick = typeof row.onClick === "function";
            row.onClick();
            """#)
        // setLowPowerMode is a promise, so the toast lands once the job queue
        // has drained -- which load()'s evaluate does on its way out.
        let result = PluginHarness.run(engine, #"""
            JSON.stringify({ setArg: setArg, toast: toast, hasClick: hasClick })
            """#)
        #expect(result.contains("\"hasClick\":true"))
        #expect(result.contains("\"setArg\":true"))
        #expect(result.contains("\"title\":\"Low Power Mode\""))
        #expect(result.contains("\"body\":\"On\""))
    }
}
