import AppKit
import MacotronEngine
import Testing
@testable import MacotronUI

@MainActor
@Suite("PluginStatusItem")
struct PluginStatusItemTests {
    @Test("each item saves its slot under its own name, not its creation index")
    func autosaveNameFollowsTheID() {
        let fan = PluginStatusItem(id: "fan")
        let power = PluginStatusItem(id: "power")
        defer { fan.remove(); power.remove() }
        #expect(fan.autosaveName == "macotron-fan")
        #expect(power.autosaveName == "macotron-power")
    }

    /// One apply() with every argument set, reported through what the item
    /// actually painted. Each argument is checked by changing only it and
    /// demanding the item change too -- a value wired to the wrong slot
    /// (or dropped) leaves the render identical.
    private struct Painted {
        var image: Data?
        var length: CGFloat
        var toolTip: String?
        var ownsMenu: Bool
    }

    private func paint(
        _ id: String,
        title: String = "Title",
        subtitle: String? = "Sub",
        color: String? = "red",
        subtitleColor: String? = "blue",
        bold: Bool = false,
        italic: Bool = false,
        secondary: Bool = false,
        minWidth: Double? = nil,
        sfSymbol: String? = "cpu",
        imagePath: String? = nil,
        onClick: (() -> Void)? = nil,
        menu: [MenuBarEntry] = []
    ) -> Painted {
        let item = PluginStatusItem(id: id)
        defer { item.remove() }
        item.apply(
            title: title, subtitle: subtitle, color: color, subtitleColor: subtitleColor,
            bold: bold, italic: italic, secondary: secondary, minWidth: minWidth,
            sfSymbol: sfSymbol, imagePath: imagePath, onClick: onClick, menu: menu
        )
        return Painted(
            image: item.renderedImage,
            length: item.renderedLength,
            toolTip: item.renderedToolTip,
            ownsMenu: item.ownsMenu
        )
    }

    @Test("every apply argument reaches the status item")
    func allArgumentsLand() throws {
        let base = paint("base")
        #expect(base.image != nil)
        // title and subtitle
        #expect(base.toolTip == "Title — Sub")
        #expect(paint("title", title: "Other").image != base.image)
        #expect(paint("subtitle", subtitle: "Other").image != base.image)
        // colors, weight, slant, secondary styling
        #expect(paint("color", color: "green").image != base.image)
        #expect(paint("subColor", subtitleColor: "green").image != base.image)
        #expect(paint("bold", bold: true).image != base.image)
        #expect(paint("italic", italic: true).image != base.image)
        #expect(paint("secondary", secondary: true).image != base.image)
        // minWidth widens the slot
        #expect(paint("minWidth", minWidth: 400).length == 400)
        #expect(base.length < 400)
        // icon sources
        #expect(paint("symbol", sfSymbol: "bolt").image != base.image)
        let file = try Self.writeIcon()
        defer { try? FileManager.default.removeItem(atPath: file) }
        #expect(paint("file", imagePath: file).image != base.image)
        // menu is handed to AppKit only when there is no click handler
        let entry = MenuBarEntry(title: "Row")
        #expect(paint("menu", menu: [entry]).ownsMenu)
        #expect(!paint("click", onClick: {}, menu: [entry]).ownsMenu)
        #expect(!base.ownsMenu)
    }

    private static func writeIcon() throws -> String {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        let path = NSTemporaryDirectory() + "macotron-status-icon-\(UUID().uuidString).png"
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }
}
