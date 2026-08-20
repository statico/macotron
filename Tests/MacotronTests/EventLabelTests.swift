import Testing
@testable import MacotronUI

@Suite("EventLabel")
struct EventLabelTests {
    @Test("known events use a plain-language name")
    func known() {
        #expect(EventLabel.displayName("audio:changed") == "Audio device changed")
        #expect(EventLabel.displayName("media:changed") == "Now Playing changed")
        #expect(EventLabel.displayName("system:wake") == "Mac woke up")
    }

    @Test("keyboard events keep the shortcut label")
    func keyboard() {
        #expect(EventLabel.displayName("keyboard:demo-windows.js/Tile Left") == "Tile Left")
    }

    @Test("unknown events fall back to a spaced name")
    func fallback() {
        #expect(EventLabel.displayName("custom:did-fire") == "Custom did fire")
    }

    @Test("schedule events use readable labels")
    func schedule() {
        #expect(EventLabel.displayName("schedule:every 1h") == "Every 1h")
        #expect(EventLabel.displayName("schedule:at 13:00") == "At 13:00")
    }
}
