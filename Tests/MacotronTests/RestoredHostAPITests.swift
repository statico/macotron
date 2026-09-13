import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

// macotron.off/.config/.module/.requirePermissions and version.modules have no
// caller in this repo, which once made them look dead. They are public plugin
// API: a third-party plugin can call them, so they stay covered here.
@MainActor
@Suite("RestoredHostAPI")
struct RestoredHostAPITests {
    @Test("off() stops one listener and leaves the event working")
    func offUnsubscribes() {
        let engine = Engine()
        engine.registerAllModules()
        let (_, error) = engine.evaluate("""
            globalThis.n = 0;
            globalThis.cb = () => { globalThis.n++; };
            $$__on("test:ping", globalThis.cb);
        """)
        #expect(error == nil)

        engine.eventBus.emit("test:ping", engine: engine)
        engine.evaluate("$$__off(\"test:ping\", globalThis.cb);")
        engine.eventBus.emit("test:ping", engine: engine)

        let (count, _) = engine.evaluate("String(globalThis.n)")
        #expect(count == "1")
    }

    @Test("version.modules reports a version per native namespace")
    func moduleVersions() {
        let engine = Engine()
        engine.addModule(SpacesModule())
        engine.registerAllModules()
        let (version, error) = engine.evaluate("String(macotron.version.modules.spaces)")
        #expect(error == nil)
        #expect(version == "1")
    }
}
