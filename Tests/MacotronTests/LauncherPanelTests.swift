import AppKit
import Testing
@testable import MacotronUI

@MainActor
@Suite("LauncherPanel")
struct LauncherPanelTests {
    @Test("is a nonactivating floating panel so it does not activate Macotron")
    func nonactivating() {
        let panel = LauncherPanel(contentView: NSView(frame: .zero), windowFrame: LauncherFrame())
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.canBecomeMain)
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.level == .floating)
        #expect(panel.isFloatingPanel)
    }
}
