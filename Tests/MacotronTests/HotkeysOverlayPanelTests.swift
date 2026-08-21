import AppKit
import Testing
@testable import MacotronUI

@MainActor
@Suite("HotkeysOverlayPanel")
struct HotkeysOverlayPanelTests {
    private static let oneRow = [ShowHotkeysRow(id: "launcher", combo: "cmd+space", label: "Launcher")]
    private static let manyRows = (0..<12).map {
        ShowHotkeysRow(id: "row-\($0)", combo: "cmd+\($0)", label: "Row \($0)")
    }

    @Test("a second Show Hotkeys dismisses the panel instead of re-presenting it")
    func toggleDismisses() {
        let panel = HotkeysOverlayPanel()
        panel.toggle(rows: Self.oneRow)
        #expect(panel.isVisible)
        panel.toggle(rows: Self.oneRow)
        #expect(!panel.isVisible)
    }

    @Test("the panel sizes itself to the rows it shows")
    func framesFollowRowCount() {
        let panel = HotkeysOverlayPanel()
        panel.toggle(rows: Self.oneRow)
        #expect(panel.frame.height == HotkeysOverlayView.height(for: Self.oneRow.count))
        panel.toggle(rows: Self.oneRow)
        panel.toggle(rows: Self.manyRows)
        #expect(panel.frame.height == HotkeysOverlayView.height(for: Self.manyRows.count))
        panel.toggle(rows: Self.manyRows)
    }
}
