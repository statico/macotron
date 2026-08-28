import AppKit
import Testing
@testable import MacotronUI

/// Regression net for the launcher's key dispatch: which keys are consumed,
/// which cmd-combos map to which action, and that everything else returns
/// false so the keystroke reaches the search field.
@MainActor
@Suite("LauncherKeyDispatch")
struct LauncherKeyDispatchTests {
    final class Recorder {
        var fired: [String] = []
        var combos: [String] = []
    }

    private func event(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [],
                       _ chars: String = "") -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode
        )!
    }

    /// Builds the view under test wired to a recorder. The only part of this
    /// suite that knows how the dispatch is plumbed.
    private func makeHandler(
        _ rec: Recorder, intercept: Bool = true, recording: Bool = false,
        escapeResult: Bool = true
    ) -> KeyEventHandler {
        KeyEventHandler(
            onArrowUp: { rec.fired.append("up") },
            onArrowDown: { rec.fired.append("down") },
            onCmdReturn: { rec.fired.append("cmdReturn") },
            onCmdK: { rec.fired.append("cmdK") },
            onCmdS: { rec.fired.append("cmdS") },
            onCmdSemicolon: { rec.fired.append("cmdSemicolon") },
            onEscape: { rec.fired.append("escape"); return escapeResult },
            onRecordedCombo: { rec.fired.append("record"); rec.combos.append($0) },
            onClearShortcut: { rec.fired.append("clear") },
            interceptListKeys: intercept,
            isRecording: recording
        )
    }

    @Test("arrows and ctrl-p/n move the selection")
    func navigation() {
        let rec = Recorder()
        let handler = makeHandler(rec)
        #expect(handler.consume(event(126)))
        #expect(handler.consume(event(125)))
        #expect(handler.consume(event(35, .control, "p")))
        #expect(handler.consume(event(45, .control, "n")))
        #expect(handler.consume(event(35, [.control, .shift], "P")))
        #expect(rec.fired == ["up", "down", "up", "down", "up"])
    }

    @Test("cmd combos map to their actions")
    func cmdCombos() {
        let rec = Recorder()
        let handler = makeHandler(rec)
        #expect(handler.consume(event(36, .command)))
        #expect(handler.consume(event(40, .command, "k")))
        #expect(handler.consume(event(1, .command, "s")))
        #expect(handler.consume(event(41, .command, ";")))
        #expect(rec.fired == ["cmdReturn", "cmdK", "cmdS", "cmdSemicolon"])
    }

    @Test("extra modifiers disqualify the cmd letter combos")
    func cmdCombosNeedNoOtherModifier() {
        let rec = Recorder()
        let handler = makeHandler(rec)
        #expect(handler.consume(event(40, [.command, .shift], "k")) == false)
        #expect(handler.consume(event(1, [.command, .option], "s")) == false)
        #expect(handler.consume(event(45, [.command, .control], "n")) == false)
        #expect(rec.fired.isEmpty)
    }

    @Test("unhandled keys propagate")
    func unhandledKeysPropagate() {
        let rec = Recorder()
        let handler = makeHandler(rec)
        #expect(handler.consume(event(0, [], "a")) == false)
        #expect(handler.consume(event(48, [], "\t")) == false)
        #expect(handler.consume(event(49, [], " ")) == false)
        #expect(rec.fired.isEmpty)
    }

    @Test("escape defers to the handler's answer")
    func escape() {
        let rec = Recorder()
        #expect(makeHandler(rec, escapeResult: true).consume(event(53)))
        #expect(makeHandler(rec, escapeResult: false).consume(event(53)) == false)
        #expect(rec.fired == ["escape", "escape"])
    }

    @Test("list keys pass through while the argument form is up")
    func interceptDisabled() {
        let rec = Recorder()
        let handler = makeHandler(rec, intercept: false)
        #expect(handler.consume(event(126)) == false)
        #expect(handler.consume(event(125)) == false)
        #expect(handler.consume(event(36, .command)) == false)
        #expect(handler.consume(event(40, .command, "k")) == false)
        #expect(handler.consume(event(35, .control, "p")) == false)
        #expect(rec.fired.isEmpty)
        // Escape still closes the form.
        #expect(handler.consume(event(53)))
        #expect(rec.fired == ["escape"])
    }

    @Test("recording swallows every key and reports the combo")
    func recording() {
        let rec = Recorder()
        let handler = makeHandler(rec, recording: true)
        #expect(handler.consume(event(0, [.command, .shift], "a")))
        #expect(rec.combos == ["shift+cmd+a"])
        #expect(handler.consume(event(51)))
        #expect(handler.consume(event(117)))
        // No modifier: not a valid combo, but still swallowed.
        #expect(handler.consume(event(0, [], "a")))
        // Escape cancels through the escape handler.
        #expect(handler.consume(event(53)))
        #expect(rec.fired == ["record", "clear", "clear", "escape"])
    }
}
