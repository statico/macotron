import AppKit
import Testing
@testable import MacotronUI

@MainActor
@Suite("PluginStatusItem")
struct PluginStatusItemTests {
    @Test("each item saves its slot under its own name, not its creation index")
    func autosaveNameFollowsTheID() {
        let fan = PluginStatusItem(id: "fan")
        let power = PluginStatusItem(id: "power")
        defer { fan.remove(); power.remove() }
        #expect(fan.autosaveName == "macotron-fan")
        #expect(power.autosaveName == "macotron-power")
    }
}
