import AppKit
import Testing
@testable import MacotronEngine
@testable import Modules

@Suite("ClipboardPlain")
struct ClipboardPlainTests {
    @Test("applyCurrentText keeps string only")
    func applyKeepsString() {
        let pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        pb.declareTypes([.html, .string], owner: nil)
        pb.setString("<b>hi</b>", forType: .html)
        pb.setString("hi", forType: .string)
        ClipboardPlain.applyCurrentText(to: pb)
        #expect(pb.string(forType: .string) == "hi")
        #expect(pb.string(forType: .html) == nil)
    }
}

@MainActor
@Suite("clipboard.setPastePlain")
struct ClipboardPastePlainTests {
    @Test("dry-run returns true without installing a tap")
    func dryRunReturnsTrue() {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(ClipboardModule())
        engine.registerAllModules()
        let (result, error) = engine.evaluate("""
            JSON.stringify({
                on: macotron.clipboard.setPastePlain(true),
                isOn: macotron.clipboard.isPastePlain(),
                off: macotron.clipboard.setPastePlain(false),
                isOff: macotron.clipboard.isPastePlain()
            })
            """)
        #expect(error == nil)
        #expect(result == #"{"on":true,"isOn":true,"off":true,"isOff":false}"#)
        let module = engine.configStore["__clipboardModule"] as? ClipboardModule
        #expect(module?.hasPasteTap == false)
    }
}
