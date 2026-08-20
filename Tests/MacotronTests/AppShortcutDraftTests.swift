import Foundation
import Testing
@testable import MacotronUI

@Suite("AppShortcutDraft")
struct AppShortcutDraftTests {
    @Test("Add stays off until an app and a shortcut are both set")
    func needsAppAndShortcut() {
        #expect(!AppShortcutDraft.canSubmit(appID: nil, combo: "cmd+shift+s", existing: []))
        #expect(!AppShortcutDraft.canSubmit(appID: "com.apple.Safari", combo: "", existing: []))
        #expect(AppShortcutDraft.canSubmit(appID: "com.apple.Safari", combo: "cmd+shift+s", existing: []))
    }

    @Test("Add stays off when the app already has a shortcut")
    func rejectsDuplicateApp() {
        #expect(!AppShortcutDraft.canSubmit(
            appID: "com.apple.Safari",
            combo: "cmd+shift+s",
            existing: ["com.apple.Safari"]
        ))
    }

    @Test("reads name and bundle id from an app bundle")
    func summaryFromURL() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let summary = AppShortcutDraft.summary(from: url)
        #expect(summary?.id == "com.apple.finder")
        #expect(summary?.name == "Finder")
    }
}
