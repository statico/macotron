import AppKit
import Testing
@testable import MacotronUI

@Suite("MenuBarIcon")
struct MenuBarIconTests {
    @Test("tinted glyph is drawn as an original image")
    func tintedIsNotTemplate() {
        #expect(MenuBarIcon.makeImage().isTemplate)
        #expect(!MenuBarIcon.makeImage(tint: .systemRed).isTemplate)
    }
}

@Suite("MenuBarBadge")
struct MenuBarBadgeTests {
    private func state(
        permissions: Bool = false, review: Int = 0, hotReload: Bool = false, updates: Int = 0
    ) -> MenuBarBadge {
        MenuBarBadge.state(
            missingPermissions: permissions, pendingReviewCount: review,
            hotReload: hotReload, pluginUpdateCount: updates
        )
    }

    @Test("plugin updates badge only once nothing is wrong")
    func updatesAreLowest() {
        #expect(state(updates: 3) == .updates)
        #expect(state(hotReload: true, updates: 3) == .hotReload)
        #expect(state(review: 1, updates: 3) == .review)
        #expect(state(permissions: true, updates: 3) == .permissions)
    }

    @Test("no updates and nothing wrong leaves the icon bare")
    func nothingToSay() {
        #expect(state() == .none)
        #expect(state(updates: 0) == .none)
    }

    @Test("the warnings keep the order they had before updates existed")
    func warningOrderUnchanged() {
        #expect(state(permissions: true, review: 2, hotReload: true) == .permissions)
        #expect(state(review: 2, hotReload: true) == .review)
        #expect(state(hotReload: true) == .hotReload)
    }

    @MainActor
    @Test("the count is spelled out for one update and for many")
    func label() {
        #expect(MenuBarManager.updateLabel(1) == "1 plugin update")
        #expect(MenuBarManager.updateLabel(4) == "4 plugin updates")
    }
}
