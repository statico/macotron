import AppKit
import Testing
@testable import MacotronEngine
@testable import MacotronUI

@Suite("PluginMenu")
struct PluginMenuTests {
    /// A repainting plugin re-applies the same icon every tick. Handing AppKit a
    /// fresh image each time re-measures an open menu and walks the row right.
    @MainActor
    @Test("re-applying the same icon keeps the same image object")
    func iconIsNotRebuilt() {
        let item = NSMenuItem()
        PluginMenu.apply(title: "CPU 21%", icon: "cpu", to: item)
        let first = item.image
        PluginMenu.apply(title: "CPU 22%", icon: "cpu", to: item)
        #expect(item.image === first)
        #expect(item.title == "CPU 22%")

        PluginMenu.apply(title: "CPU 23%", icon: "memorychip", to: item)
        #expect(item.image !== first)

        PluginMenu.apply(title: "CPU 24%", icon: nil, to: item)
        #expect(item.image == nil)
    }

    @MainActor
    @Test("a short icon goes in the title, not the image")
    func emojiIcon() {
        let item = NSMenuItem()
        PluginMenu.apply(title: "Sleep", icon: "☕", to: item)
        #expect(item.title == "☕ Sleep")
        #expect(item.image == nil)
    }

    /// The page would restart its animations and refetch its images on every
    /// repaint if the row reloaded whenever the plugin redrew its menu.
    @MainActor
    @Test("a web row only reloads when its markup changes")
    func webRowIsReused() {
        var boxes: [PluginMenu.Action] = []
        let menu = PluginMenu.make(
            [MenuBarEntry(title: "", html: "<b>one</b>", width: 200, height: 100)],
            retaining: &boxes
        )
        let view = menu.items.first?.view as? MenuWebView
        #expect(view?.html == "<b>one</b>")
        #expect(view?.frame.size == NSSize(width: 200, height: 100))

        PluginMenu.sync(menu, to: [MenuBarEntry(title: "", html: "<b>one</b>")], retaining: &boxes)
        #expect(menu.items.first?.view === view)
        #expect(view?.html == "<b>one</b>")

        PluginMenu.sync(menu, to: [MenuBarEntry(title: "", html: "<b>two</b>")], retaining: &boxes)
        #expect(menu.items.first?.view === view)
        #expect(view?.html == "<b>two</b>")

        // Swapping a web row for a plain one has to rebuild the menu.
        PluginMenu.sync(menu, to: [MenuBarEntry(title: "Plain")], retaining: &boxes)
        #expect(menu.items.first?.view == nil)
        #expect(menu.items.first?.title == "Plain")
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

@Suite("PluginFilter")
struct PluginFilterTests {
    private func summary(_ title: String, _ file: String, _ description: String = "") -> ModuleSummary {
        ModuleSummary(filename: file, title: title, description: description)
    }

    @MainActor
    @Test("an empty query keeps everything")
    func empty() {
        #expect(PluginFilter.matches(summary("Fan", "fan.js"), query: "  "))
    }

    @MainActor
    @Test("matches title, filename, and description, ignoring case")
    func fields() {
        let fan = summary("Fan Control", "fan.js", "Spin the fans up")
        #expect(PluginFilter.matches(fan, query: "fan cont"))
        #expect(PluginFilter.matches(fan, query: "FAN.JS"))
        #expect(PluginFilter.matches(fan, query: "spin"))
        #expect(!PluginFilter.matches(fan, query: "battery"))
    }

    @MainActor
    @Test("a space cannot start a filter but can extend one")
    func spaceHandling() {
        #expect(!PluginFilter.accepts(" ", existing: ""))
        #expect(PluginFilter.accepts(" ", existing: "fan"))
        #expect(PluginFilter.accepts("f", existing: ""))
        #expect(!PluginFilter.accepts("ab", existing: ""))
        #expect(!PluginFilter.accepts("\t", existing: "fan"))
    }
}
