import AppKit
import Testing
@testable import MacotronUI

@Suite("CommandHold")
struct CommandHoldTests {
    @Test("command down shows Reveal only when the app is active and not recording")
    func revealRules() {
        #expect(CommandHold.isHeld(commandDown: true, recording: false, appActive: true))
        #expect(!CommandHold.isHeld(commandDown: true, recording: true, appActive: true))
        #expect(!CommandHold.isHeld(commandDown: true, recording: false, appActive: false))
        #expect(!CommandHold.isHeld(commandDown: false, recording: false, appActive: true))
    }

    @Test("command flag uses the device-independent mask")
    func commandFlag() {
        #expect(CommandHold.commandDown(.command))
        #expect(CommandHold.commandDown([.command, .shift]))
        #expect(!CommandHold.commandDown([]))
        #expect(!CommandHold.commandDown(.shift))
    }
}
