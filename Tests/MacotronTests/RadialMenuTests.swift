import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Radial menu")
struct RadialMenuTests {
    /// windows.js only needs enough of the host to finish loading: it binds
    /// hotkeys, configures snapping, and registers commands at load time.
    static let mock = #"""
        var macotron = {
            plugin: () => ({}),
            keyboard: { on: () => {} },
            window: { snap: () => {}, focused: () => null },
            command: () => {},
            notify: { toast: () => {} },
            display: { list: () => [] },
            panel: { open: () => 1, onMessage: () => {}, close: () => {} }
        };
        """#

    static func zones(_ expression: String) throws -> String {
        try PluginHarness.eval(plugin: "windows.js", mock: mock, extra: expression)
    }

    @Test("each compass direction picks its own zone")
    func compass() throws {
        // Screen coordinates: +y is down, so a negative dy is north.
        let result = try Self.zones(#"""
            JSON.stringify([
                radialZone(100, 0), radialZone(70, 70), radialZone(0, 100), radialZone(-70, 70),
                radialZone(-100, 0), radialZone(-70, -70), radialZone(0, -100), radialZone(70, -70)
            ])
            """#)
        #expect(result == #"["right","br","bottom","bl","left","tl","top","tr"]"#)
    }

    @Test("the dead zone is maximize above the middle and center below it")
    func deadZone() throws {
        #expect(try Self.zones("radialZone(0, -10)") == "full")
        #expect(try Self.zones("radialZone(0, 10)") == "center")
        #expect(try Self.zones("radialZone(30, 20)") == "center")
        // Just outside the dead zone the wedges take over again.
        #expect(try Self.zones("radialZone(0, 41)") == "bottom")
    }

    @Test("angles wrap across the 0/360 boundary")
    func wrap() throws {
        // Both sides of due east belong to the same wedge, and a whole extra
        // turn changes nothing.
        #expect(try Self.zones("radialZone(100, -20)") == "right")
        #expect(try Self.zones("radialZone(100, 20)") == "right")
        // 22.4 degrees below east stays east; 22.6 tips into the corner.
        #expect(try Self.zones("radialZone(100, 100 * Math.tan(22.4 * Math.PI / 180))") == "right")
        #expect(try Self.zones("radialZone(100, 100 * Math.tan(22.6 * Math.PI / 180))") == "br")
    }
}
