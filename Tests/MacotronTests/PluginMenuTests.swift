import AppKit
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@Suite("PluginMenu")
struct PluginMenuTests {
    @Test("menu items keep working after the host drops its action list")
    func itemsRetainActions() {
        var ran = false
        var boxes: [PluginMenu.Action] = []
        let menu = PluginMenu.make(
            [MenuBarEntry(title: "Stop", onClick: { ran = true })],
            retaining: &boxes
        )
        boxes.removeAll()
        let item = menu.items[0]
        guard let target = item.target, let action = item.action else {
            Issue.record("Stop lost its action")
            return
        }
        _ = target.perform(action, with: item)
        #expect(ran)
    }

    @Test("items without onClick stay enabled")
    func labelItemsEnabled() {
        var boxes: [PluginMenu.Action] = []
        let menu = PluginMenu.make(
            [MenuBarEntry(title: "Feels like 62°")],
            retaining: &boxes
        )
        let item = menu.items[0]
        #expect(item.isEnabled)
        #expect(item.action != nil)
    }
}
