import Testing
@testable import MacotronEngine
@testable import Modules

@MainActor
final class StatusReloadRecorder: MenuBarModuleDelegate {
    var removedAll = 0
    var began = 0
    var finished = 0
    var iconColors: [String?] = []

    func menuBarAddItem(id: String, title: String, icon: String?, section: String?, onClick: (() -> Void)?, menu: [MenuBarEntry]) {}
    func menuBarUpdateItem(id: String, title: String?, icon: String?) {}
    func menuBarRemoveItem(id: String) {}
    func menuBarSetIcon(sfSymbolName: String) {}
    func menuBarSetIconColor(color: String?) { iconColors.append(color) }
    func menuBarSetTitle(text: String) {}
    func menuBarSetStatus(
        id: String, title: String, subtitle: String?, color: String?, subtitleColor: String?,
        bold: Bool, italic: Bool, secondary: Bool, minWidth: Double?, sfSymbol: String?,
        imagePath: String?, onClick: (() -> Void)?, menu: [MenuBarEntry]
    ) {}
    func menuBarRemoveStatus(id: String) {}
    func menuBarRemoveAllStatus() { removedAll += 1 }
    func menuBarBeginStatusReload() { began += 1 }
    func menuBarFinishStatusReload() { finished += 1 }
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
}
