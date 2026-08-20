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

    @Test("sync updates titles on the same items")
    func syncUpdatesTitles() {
        var boxes: [PluginMenu.Action] = []
        let menu = PluginMenu.make(
            [MenuBarEntry(title: "CPU 1%")],
            retaining: &boxes
        )
        let item = menu.items[0]
        PluginMenu.sync(menu, to: [MenuBarEntry(title: "CPU 2%")], retaining: &boxes)
        #expect(menu.items[0] === item)
        #expect(menu.items[0].title == "CPU 2%")
    }

    @Test("sync rebuilds when the shape changes")
    func syncRebuildsShape() {
        var boxes: [PluginMenu.Action] = []
        let menu = PluginMenu.make(
            [MenuBarEntry(title: "CPU 1%")],
            retaining: &boxes
        )
        PluginMenu.sync(
            menu,
            to: [MenuBarEntry(title: "CPU 1%"), MenuBarEntry(title: "GPU 2%")],
            retaining: &boxes
        )
        #expect(menu.items.map(\.title) == ["CPU 1%", "GPU 2%"])
    }
}
