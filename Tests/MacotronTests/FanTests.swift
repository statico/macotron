import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Fan")
struct FanTests {
    @Test("full blast toggle toasts on and off")
    func toggleToasts() throws {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/fan.js")
        let pluginSource = try String(contentsOf: pluginURL, encoding: .utf8)
        let harness = """
            var statusConfig = null;
            var floor = null;
            var toasts = [];
            var stored = {};
            var localStorage = {
                getItem: (key) => (key in stored ? stored[key] : null),
                setItem: (key, value) => { stored[key] = String(value); }
            };
            var macotron = {
                plugin: () => ({}),
                system: {
                    fans: () => ({
                        available: true,
                        controllable: true,
                        floor: floor,
                        fans: [{ index: 0, rpm: 2000, min: 1000, max: 5000 }]
                    }),
                    setFanFloor: (percent) => {
                        floor = percent;
                        return Promise.resolve({
                            available: true,
                            controllable: true,
                            floor: percent,
                            fans: [{ index: 0, rpm: 2000, min: 1000, max: 5000 }]
                        });
                    }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                checks: () => {},
                settings: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: (title, body) => { toasts.push({ title: title, body: body }); } }
            };
            \(pluginSource)
            statusConfig.onClick();
            statusConfig.onClick();
            """
        let engine = Engine()
        let (_, error) = engine.evaluate(harness, filename: pluginURL.path)
        #expect(error == nil)
        // setFanFloor is a promise now, so the toasts land once the job queue
        // has drained -- which the first evaluate does on its way out.
        let (result, readError) = engine.evaluate("JSON.stringify(toasts)")
        #expect(readError == nil)
        // The toast has to name the speed it set; "On" told the user nothing.
        #expect(result?.contains("\"body\":\"minimum speed: 100%\"") == true)
        #expect(result?.contains("\"body\":\"Set to automatic speed\"") == true)
    }
}
