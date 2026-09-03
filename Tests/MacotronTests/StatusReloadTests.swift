import Testing
@testable import MacotronEngine
@testable import Modules

/// Every argument menubar.status hands the delegate, so a change to the option
/// read shows up as a failed field rather than as a silently dropped option.
struct StatusCall {
    var id: String
    var title: String
    var subtitle: String?
    var color: String?
    var subtitleColor: String?
    var bold: Bool
    var italic: Bool
    var secondary: Bool
    var minWidth: Double?
    var sfSymbol: String?
    var imagePath: String?
    var hasClick: Bool
    var menu: [MenuBarEntry]
    var required: Bool
}

@MainActor
final class StatusReloadRecorder: MenuBarModuleDelegate {
    var removedAll = 0
    var began = 0
    var finished = 0
    var iconColors: [String?] = []
    var statuses: [StatusCall] = []

    func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?, menu: [MenuBarEntry]) {}
    func updateItem(id: String, title: String?, icon: String?) {}
    func removeItem(id: String) {}
    func setIcon(_ sfSymbolName: String) {}
    func setIconColor(_ color: String?) { iconColors.append(color) }
    func setTitle(_ text: String) {}
    func setStatus(
        id: String, title: String, subtitle: String?, color: String?, subtitleColor: String?,
        bold: Bool, italic: Bool, secondary: Bool, minWidth: Double?, sfSymbol: String?,
        imagePath: String?, onClick: (() -> Void)?, menu: [MenuBarEntry], required: Bool
    ) {
        statuses.append(StatusCall(
            id: id, title: title, subtitle: subtitle, color: color, subtitleColor: subtitleColor,
            bold: bold, italic: italic, secondary: secondary, minWidth: minWidth,
            sfSymbol: sfSymbol, imagePath: imagePath, hasClick: onClick != nil,
            menu: menu, required: required
        ))
    }
    func removeStatus(id: String) {}
    func isStatusShowing(id: String) -> Bool { true }
    func removeAllStatus() { removedAll += 1 }
    func beginStatusReload() { began += 1 }
    func finishStatusReload() { finished += 1 }
}

@MainActor
@Suite("StatusReload")
struct StatusReloadTests {
    @Test("cleanup keeps extra status items and sweeps after plugins reload")
    func cleanupDoesNotClearStatusItems() {
        let engine = Engine()
        let mod = MenuBarModule()
        let rec = StatusReloadRecorder()
        mod.delegate = rec
        engine.addModule(mod)
        engine.registerAllModules()

        mod.cleanup()
        #expect(rec.removedAll == 0)
        #expect(rec.began == 1)

        mod.didReload()
        #expect(rec.finished == 1)
        #expect(rec.removedAll == 0)
    }

    @Test("setIconColor forwards a color and null clears it")
    func setIconColorBridge() {
        let engine = Engine()
        let mod = MenuBarModule()
        let rec = StatusReloadRecorder()
        mod.delegate = rec
        engine.addModule(mod)
        engine.registerAllModules()

        let (_, error) = engine.evaluate("macotron.menubar.setIconColor('#FF3B30'); macotron.menubar.setIconColor(null)")
        #expect(error == nil)
        #expect(rec.iconColors.count == 2)
        #expect(rec.iconColors[0] == "#FF3B30")
        #expect(rec.iconColors[1] == nil)
    }

    @Test("status carries every option through to the delegate")
    func statusOptionSurface() {
        let engine = Engine()
        let mod = MenuBarModule()
        let rec = StatusReloadRecorder()
        mod.delegate = rec
        engine.addModule(mod)
        engine.registerAllModules()

        let (_, error) = engine.evaluate("""
            macotron.menubar.status('full', {
                title: 'T', subtitle: 'S', color: '#111', subtitleColor: '#222',
                bold: true, italic: true, secondary: true, minWidth: 42,
                sfSymbol: 'bolt', image: '/tmp/x.png', required: false,
                onClick: () => {},
                menu: [
                    'plain',
                    { title: 'nested', icon: 'gear', onClick: () => {}, menu: ['child'] },
                    { title: 'inline', buttons: ['a', 'b'] },
                    { title: 'web', html: '<b>hi</b>', width: 300, height: 200 }
                ]
            })
            """)
        #expect(error == nil)
        #expect(rec.statuses.count == 1)
        let call = rec.statuses[0]
        #expect(call.id == "full")
        #expect(call.title == "T")
        #expect(call.subtitle == "S")
        #expect(call.color == "#111")
        #expect(call.subtitleColor == "#222")
        #expect(call.bold)
        #expect(call.italic)
        #expect(call.secondary)
        #expect(call.minWidth == 42)
        #expect(call.sfSymbol == "bolt")
        #expect(call.imagePath == "/tmp/x.png")
        #expect(call.hasClick)
        #expect(call.required == false)
        #expect(call.menu.count == 4)
        #expect(call.menu[0].title == "plain")
        #expect(call.menu[1].title == "nested")
        #expect(call.menu[1].icon == "gear")
        #expect(call.menu[1].onClick != nil)
        #expect(call.menu[1].children.map(\.title) == ["child"])
        #expect(call.menu[1].inline == false)
        #expect(call.menu[2].inline)
        #expect(call.menu[2].children.map(\.title) == ["a", "b"])
        #expect(call.menu[3].html == "<b>hi</b>")
        #expect(call.menu[3].size.width == 300)
        #expect(call.menu[3].size.height == 200)
    }

    @Test("status defaults when the options object is empty")
    func statusDefaults() {
        let engine = Engine()
        let mod = MenuBarModule()
        let rec = StatusReloadRecorder()
        mod.delegate = rec
        engine.addModule(mod)
        engine.registerAllModules()

        let (_, error) = engine.evaluate("macotron.menubar.status('bare', {})")
        #expect(error == nil)
        #expect(rec.statuses.count == 1)
        let call = rec.statuses[0]
        // A missing title falls back to the id, not to the string "undefined".
        #expect(call.title == "bare")
        #expect(call.subtitle == nil)
        #expect(call.color == nil)
        #expect(call.subtitleColor == nil)
        #expect(call.bold == false)
        #expect(call.italic == false)
        #expect(call.secondary == false)
        #expect(call.minWidth == nil)
        #expect(call.sfSymbol == nil)
        #expect(call.imagePath == nil)
        #expect(call.hasClick == false)
        #expect(call.menu.isEmpty)
        // Absent `required` means required: a plugin that asks for a status
        // item gets one unless it opts out.
        #expect(call.required)
    }

    @Test("status falls back from sfSymbol to icon")
    func statusIconAlias() {
        let engine = Engine()
        let mod = MenuBarModule()
        let rec = StatusReloadRecorder()
        mod.delegate = rec
        engine.addModule(mod)
        engine.registerAllModules()

        let (_, error) = engine.evaluate("""
            macotron.menubar.status('a', { icon: 'gear' });
            macotron.menubar.status('b', { icon: 'gear', sfSymbol: 'bolt' });
            """)
        #expect(error == nil)
        #expect(rec.statuses.map(\.sfSymbol) == ["gear", "bolt"])
    }
}
