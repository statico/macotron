import AppKit
import Foundation
import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
private func dryEngine(_ modules: [NativeModule]) -> Engine {
    let engine = Engine()
    engine.dryRun = true
    for module in modules { engine.addModule(module) }
    engine.registerAllModules()
    return engine
}

@MainActor
@Suite("dryRun stubs")
struct DryRunStubTests {
    @Test("shell.run resolves a stub without spawning")
    func shellRun() {
        let marker = NSTemporaryDirectory() + "macotron-dryrun-shell-\(UUID().uuidString)"
        let engine = dryEngine([ShellModule()])
        let (_, error) = engine.evaluate("""
            globalThis.out = null;
            macotron.shell.run('touch', ['\(marker)']).then(r => {
              // Field-by-field, not JSON.stringify: property order is not part
              // of the contract and asserting it just breaks on a refactor.
              globalThis.out = [r.stdout, r.stderr, r.exitCode].join('|');
            });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "||0")
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("fs.write and fs.rename do not touch disk; fs.watch returns a no-op stop")
    func fs() throws {
        let dir = NSTemporaryDirectory() + "macotron-dryrun-fs-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let src = dir + "/src.txt"
        try "hello".write(toFile: src, atomically: true, encoding: .utf8)

        let engine = dryEngine([FileSystemModule()])
        let (result, error) = engine.evaluate("""
            macotron.fs.write('\(dir)/new.txt', 'x');
            macotron.fs.rename('\(src)', '\(dir)/moved.txt');
            const stop = macotron.fs.watch('\(dir)', () => {});
            stop();
            typeof stop
            """)
        #expect(error == nil)
        #expect(result == "function")
        #expect(!FileManager.default.fileExists(atPath: dir + "/new.txt"))
        #expect(FileManager.default.fileExists(atPath: src))
        #expect(!FileManager.default.fileExists(atPath: dir + "/moved.txt"))
    }

    @Test("keychain.set and delete are inert")
    func keychain() {
        let key = "macotron-dryrun-test-\(UUID().uuidString)"
        let engine = dryEngine([KeychainModule()])
        let (result, error) = engine.evaluate("""
            macotron.keychain.set('\(key)', 'secret');
            macotron.keychain.delete('\(key)');
            macotron.keychain.has('\(key)')
            """)
        #expect(error == nil)
        #expect(result == "false")
        #expect(KeychainStore.read(account: key) == nil)
    }

    @Test("http methods return a stub without hitting the network")
    func http() {
        let engine = dryEngine([HTTPModule()])
        let (result, error) = engine.evaluate("""
            JSON.stringify([
                macotron.http.get('http://127.0.0.1:1/'),
                macotron.http.post('http://127.0.0.1:1/', '{}'),
                macotron.http.put('http://127.0.0.1:1/', '{}'),
                macotron.http.delete('http://127.0.0.1:1/'),
            ].map(r => r.status))
            """)
        #expect(error == nil)
        #expect(result == "[0,0,0,0]")
    }

    @Test("ai chat and stream resolve empty without calling a provider")
    func ai() {
        let engine = dryEngine([AIModule()])
        let (_, error) = engine.evaluate("""
            globalThis.chatOut = null;
            globalThis.streamOut = null;
            macotron.ai.local().chat('hi').then(t => { globalThis.chatOut = 'resolved:' + t; });
            macotron.ai.local().stream('hi', { onChunk: () => {} }).then(t => { globalThis.streamOut = 'resolved:' + t; });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.chatOut + '|' + globalThis.streamOut")
        #expect(result == "resolved:|resolved:")
    }

    @Test("url.open reports success without opening")
    func urlOpen() {
        let engine = dryEngine([URLSchemeModule()])
        let (result, error) = engine.evaluate("macotron.url.open('https://example.com')")
        #expect(error == nil)
        #expect(result == "true")
    }

    @Test("shortcuts.run reports success without spawning")
    func shortcutsRun() {
        let engine = dryEngine([ShortcutsModule()])
        let (_, error) = engine.evaluate("""
            globalThis.out = null;
            macotron.shortcuts.run('Does Not Exist').then(ok => { globalThis.out = ok; });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "true")
    }

    @Test("hid send is inert")
    func hidSend() {
        let engine = dryEngine([HIDModule()])
        let (result, error) = engine.evaluate("""
            JSON.stringify([
                macotron.hid.sendOutput('dev', [1, 2]).ok,
                macotron.hid.sendFeature('dev', [1, 2]).ok,
            ])
            """)
        #expect(error == nil)
        #expect(result == "[true,true]")
    }

    @Test("app launch/switch/quit/hide are inert")
    func app() {
        let engine = dryEngine([AppModule()])
        let (result, error) = engine.evaluate("""
            JSON.stringify([
                macotron.app.launch('com.apple.Finder'),
                macotron.app.switch('com.apple.Finder'),
                macotron.app.quit('com.apple.Finder'),
                macotron.app.hide('com.apple.Finder'),
            ])
            """)
        #expect(error == nil)
        #expect(result == "[true,true,true,true]")
    }

    @Test("window mutators are inert")
    func window() {
        let engine = dryEngine([WindowModule()])
        let (result, error) = engine.evaluate("""
            JSON.stringify([
                macotron.window.focus(1),
                macotron.window.move(1, { x: 0, y: 0 }),
                macotron.window.moveToFraction(1, { x: 0, y: 0, w: 1, h: 1 }),
                macotron.window.minimize(1),
                macotron.window.close(1),
                macotron.window.setFullscreen(1, true),
                macotron.window.restore([{ id: 1, app: 'X' }]).restored,
            ])
            """)
        #expect(error == nil)
        #expect(result == "[true,true,true,true,true,true,1]")
    }

    @Test("qr.show and qr.scan are inert")
    func qr() {
        let engine = dryEngine([QRModule()])
        let (_, error) = engine.evaluate("""
            macotron.qr.show('hello');
            globalThis.scanOut = 'pending';
            macotron.qr.scan().then(v => { globalThis.scanOut = String(v); });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.scanOut")
        #expect(result == "null")
    }

    @Test("ocr.recognize resolves empty without running Vision")
    func ocr() {
        let engine = dryEngine([OCRModule()])
        let (_, error) = engine.evaluate("""
            globalThis.ocrOut = 'pending';
            macotron.ocr.recognize({ image: 'aGk=' }).then(t => { globalThis.ocrOut = 'resolved:' + t; });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.ocrOut")
        #expect(result == "resolved:")
    }

    @Test("snippets.insert and setExpansionEnabled are inert")
    func snippets() {
        let before = NSPasteboard.general.changeCount
        let engine = dryEngine([SnippetsModule()])
        let (result, error) = engine.evaluate("""
            macotron.snippets.set('abbr', 'body');
            macotron.snippets.insert('abbr');
            macotron.snippets.setExpansionEnabled(true)
            """)
        #expect(error == nil)
        #expect(result == "true")
        #expect(NSPasteboard.general.changeCount == before)
        let module = engine.configStore["__snippetsModule"] as? SnippetsModule
        #expect(module?.hasEventTap == false)
    }

    @Test("calendar.upcoming returns empty without requesting access")
    func calendar() {
        let engine = dryEngine([CalendarModule()])
        let (result, error) = engine.evaluate("JSON.stringify(macotron.calendar.upcoming())")
        #expect(error == nil)
        #expect(result == "[]")
    }
}
