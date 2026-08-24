import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
@Suite("URL scheme events", .serialized)
struct URLSchemeEventTests {
    @Test("URL received during startup dispatches after handlers load")
    func startupURLDispatchesAfterReload() {
        let engine = Engine()
        let module = URLSchemeModule()
        engine.addModule(module)
        engine.registerAllModules()
        defer { module.cleanup() }

        URLSchemeModule.handle(
            [URL(string: "https://youtube.com/watch")!],
            sourceBundle: "com.apple.Safari"
        )

        let (_, error) = engine.evaluate("""
            globalThis.receivedEvents = [];
            macotron.url.on("https", "youtube.com", event => {
                globalThis.receivedEvents.push([event.url, event.sourceBundle]);
            });
            """)
        #expect(error == nil)

        engine.notifyModulesDidReload()

        let (result, readError) = engine.evaluate("JSON.stringify(globalThis.receivedEvents)")
        #expect(readError == nil)
        #expect(result == #"[["https://youtube.com/watch","com.apple.Safari"]]"#)
    }

    @Test("URL received during reload dispatches in the new context")
    func reloadURLDispatchesInNewContext() {
        let engine = Engine()
        let module = URLSchemeModule()
        engine.addModule(module)
        engine.registerAllModules()
        engine.notifyModulesDidReload()
        defer { module.cleanup() }

        engine.reset()
        URLSchemeModule.handle([URL(string: "https://example.com/reload")!])

        let (_, error) = engine.evaluate("""
            globalThis.reloadURLs = [];
            macotron.url.on("https", "example.com", event => {
                globalThis.reloadURLs.push(event.url);
            });
            """)
        #expect(error == nil)

        engine.notifyModulesDidReload()

        let (result, readError) = engine.evaluate("JSON.stringify(globalThis.reloadURLs)")
        #expect(readError == nil)
        #expect(result == #"["https://example.com/reload"]"#)
    }

    @Test("JavaScript regular expression keeps sticky matching semantics")
    func regexKeepsJavaScriptSemantics() {
        let engine = Engine()
        let module = URLSchemeModule()
        engine.addModule(module)
        engine.registerAllModules()
        defer { module.cleanup() }

        let (_, error) = engine.evaluate("""
            globalThis.regexURLs = [];
            globalThis.wildcardURLs = [];
            macotron.url.on("https", /youtube/y, event => {
                globalThis.regexURLs.push(event.url);
            });
            macotron.url.on("https", "*", event => {
                globalThis.wildcardURLs.push(event.url);
            });
            """)
        #expect(error == nil)
        engine.notifyModulesDidReload()

        URLSchemeModule.handle([
            URL(string: "https://xyoutube.com/watch")!,
            URL(string: "https://youtube.com/watch")!,
        ])

        let (result, readError) = engine.evaluate(
            "JSON.stringify([globalThis.regexURLs, globalThis.wildcardURLs])"
        )
        #expect(readError == nil)
        #expect(result == #"[["https://youtube.com/watch"],["https://xyoutube.com/watch"]]"#)
    }
}
