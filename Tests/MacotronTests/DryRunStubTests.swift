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
        let (_, error) = engine.evaluate("""
            globalThis.out = null;
            Promise.all([
                macotron.http.get('http://127.0.0.1:1/'),
                macotron.http.post('http://127.0.0.1:1/', '{}'),
                macotron.http.put('http://127.0.0.1:1/', '{}'),
                macotron.http.delete('http://127.0.0.1:1/'),
            ]).then(rs => { globalThis.out = JSON.stringify(rs.map(r => r.status)); });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "[0,0,0,0]")

        // Name and arity come off the same table row as the HTTP method and
        // the body flag, so a misrouted magic index shows up here.
        let (shape, shapeError) = engine.evaluate("""
            ['get', 'post', 'put', 'delete']
                .map(n => macotron.http[n].name + '/' + macotron.http[n].length).join(',')
            """)
        #expect(shapeError == nil)
        #expect(shape == "get/2,post/3,put/3,delete/2")
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

    /// The inert-and-returns-true modules, on one engine: each of these only
    /// has to report success without doing anything, so they do not each need
    /// an engine of their own.
    @Test("url, shortcuts, hid, app and window calls are inert")
    func inertModules() {
        let engine = dryEngine([URLSchemeModule(), ShortcutsModule(), HIDModule(), AppModule(), WindowModule()])
        let (result, error) = engine.evaluate("""
            globalThis.shortcutOut = null;
            macotron.shortcuts.run('Does Not Exist').then(ok => { globalThis.shortcutOut = ok; });
            JSON.stringify([
                macotron.url.open('https://example.com'),
                macotron.hid.sendOutput('dev', [1, 2]).ok,
                macotron.hid.sendFeature('dev', [1, 2]).ok,
                macotron.app.launch('com.apple.Finder'),
                macotron.app.switch('com.apple.Finder'),
                macotron.app.quit('com.apple.Finder'),
                macotron.app.hide('com.apple.Finder'),
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
        #expect(result == "[true,true,true,true,true,true,true,true,true,true,true,true,true,1]")
        #expect(engine.evaluate("globalThis.shortcutOut").0 == "true")
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

    @Test("screen.capture and pickColor are inert")
    func screen() {
        let engine = dryEngine([ScreenModule()])
        let (_, error) = engine.evaluate("""
            globalThis.capOut = 'pending';
            macotron.screen.capture().then(v => { globalThis.capOut = 'resolved:' + v; });
            globalThis.selOut = String(macotron.screen.capture({ selection: true }));
            globalThis.colorOut = String(macotron.screen.pickColor());
            """)
        #expect(error == nil)
        #expect(engine.evaluate("globalThis.capOut").0 == "resolved:")
        #expect(engine.evaluate("globalThis.selOut").0 == "")
        #expect(engine.evaluate("globalThis.colorOut").0 == "null")
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
        let (_, error) = engine.evaluate("""
            globalThis.out = null;
            macotron.calendar.upcoming().then(r => { globalThis.out = JSON.stringify(r); });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "[]")
    }
}
