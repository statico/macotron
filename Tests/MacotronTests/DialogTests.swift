import AppKit
import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("Dialog")
struct DialogTests {
    @Test("confirm OK is true and cancel is false")
    func confirmButtons() {
        let ok = Dialog.confirm("Lock the screen?", dryRun: false) { alert in
            #expect(alert.messageText == "Lock the screen?")
            #expect(alert.buttons.map(\.title) == ["OK", "Cancel"])
            return .alertFirstButtonReturn
        }
        #expect(ok)
        #expect(!Dialog.confirm("Nope", dryRun: false) { _ in .alertSecondButtonReturn })
    }

    @Test("prompt returns the field text or null")
    func prompt() {
        let text = Dialog.prompt("Name", defaultValue: "Ian", dryRun: false) { alert in
            #expect(alert.messageText == "Name")
            (alert.accessoryView as? NSTextField)?.stringValue = "Ada"
            return .alertFirstButtonReturn
        }
        #expect(text == "Ada")
        #expect(Dialog.prompt("Name", defaultValue: "Ian", dryRun: false) { _ in
            .alertSecondButtonReturn
        } == nil)
    }

    @Test("dry run does not present an alert")
    func dryRun() {
        var shown = 0
        let run: (NSAlert) -> NSApplication.ModalResponse = { _ in
            shown += 1
            return .alertFirstButtonReturn
        }
        Dialog.alert("hi", dryRun: true, run: run)
        #expect(!Dialog.confirm("hi", dryRun: true, run: run))
        #expect(Dialog.prompt("hi", defaultValue: "x", dryRun: true, run: run) == nil)
        #expect(shown == 0)
    }

    @Test("JS alert confirm and prompt match the browser globals")
    func jsGlobals() {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(DialogModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate("""
            JSON.stringify({
                types: [typeof alert, typeof confirm, typeof prompt],
                confirm: confirm("x"),
                prompt: prompt("x", "y"),
                same: macotron.confirm === confirm
            })
            """)
        #expect(error == nil)
        #expect(result?.contains(#""types":["function","function","function"]"#) == true)
        #expect(result?.contains(#""confirm":false"#) == true)
        #expect(result?.contains(#""prompt":null"#) == true)
        #expect(result?.contains(#""same":true"#) == true)
    }
}
