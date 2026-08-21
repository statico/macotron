import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Fan")
struct FanTests {
    @Test("full blast toggle toasts on and off")
    func toggleToasts() throws {
        let demoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Examples/plugins/fan.js")
        let demo = try String(contentsOf: demoURL, encoding: .utf8)
        let source = """
            var statusConfig = null;
            var floor = null;
            var toasts = [];
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
                        return {
                            available: true,
                            controllable: true,
                            floor: percent,
                            fans: [{ index: 0, rpm: 2000, min: 1000, max: 5000 }]
                        };
                    }
                },
                menubar: { status: (id, cfg) => { statusConfig = cfg; } },
                checks: () => {},
                settings: { open: () => {} },
                every: () => {},
                command: () => {},
                notify: { toast: (title, body) => { toasts.push({ title: title, body: body }); } }
            };
            \(demo)
            statusConfig.onClick();
            statusConfig.onClick();
            JSON.stringify(toasts)
            """
        let engine = Engine()
        let (result, error) = engine.evaluate(source, filename: demoURL.path)
        #expect(error == nil)
        #expect(result?.contains("\"body\":\"On\"") == true)
        #expect(result?.contains("\"body\":\"Off\"") == true)
    }
}
