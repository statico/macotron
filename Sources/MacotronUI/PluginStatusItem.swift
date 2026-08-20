import AppKit
import MacotronEngine

@MainActor
final class PluginStatusItem: NSObject {
    let id: String
    private let item: NSStatusItem
    private var onClick: (() -> Void)?
    private var menuKeep: [PluginMenu.Action] = []
    private var dropdown: NSMenu?

    init(id: String) {
        self.id = id
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func apply(
        title: String,
        subtitle: String?,
        color: String?,
        subtitleColor: String?,
        bold: Bool,
        italic: Bool,
        secondary: Bool,
        minWidth: Double?,
        sfSymbol: String?,
        imagePath: String?,
        onClick: (() -> Void)?,
        menu: [MenuBarEntry] = []
    ) {
        self.onClick = onClick
        menuKeep.removeAll()
        if menu.isEmpty {
            dropdown = nil
        } else {
            dropdown = PluginMenu.make(menu, retaining: &menuKeep)
        }
        item.menu = nil
        let button = item.button
        button?.target = self
        button?.action = #selector(clicked)
        let nsColor = Self.parseColor(color)
        let nsSubtitleColor = Self.parseColor(subtitleColor)
        let iconOnly = title.isEmpty && (subtitle ?? "").isEmpty
        let twoLine = !(subtitle ?? "").isEmpty
        let image = Self.loadImage(sfSymbol: sfSymbol, path: imagePath, color: iconOnly ? nsColor : nil)
        button?.contentTintColor = nil
        let lines = StatusLineStyle.lines(
            title: title,
            subtitle: subtitle,
            color: nsColor,
            subtitleColor: nsSubtitleColor,
            bold: bold,
            italic: italic,
            secondary: secondary
        )
        if twoLine {
            // NSButtonCell does not vertically center multi-line titles, so
            // compose icon and text into one image; buttons center images.
            let height = button?.window?.frame.height ?? NSStatusBar.system.thickness
            button?.image = StatusLineStyle.image(icon: image, lines: lines, height: height)
            button?.imagePosition = .imageOnly
            button?.attributedTitle = NSAttributedString()
        } else {
            button?.image = image
            button?.imagePosition = iconOnly ? .imageOnly : .imageLeading
            button?.attributedTitle = lines.first ?? NSAttributedString()
        }
        item.length = NSStatusItem.variableLength
        if let button,
           let length = StatusLineStyle.length(
               naturalWidth: ceil(button.fittingSize.width),
               minWidth: minWidth
           ) {
            item.length = length
        }
        button?.toolTip = subtitle.map { "\(title) — \($0)" } ?? title
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        let event = item.button?.window?.currentEvent ?? NSApp.currentEvent
        let menuClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if (menuClick || onClick == nil), let dropdown, let button = item.button {
            if let event, event.type == .rightMouseUp || event.type == .leftMouseUp {
                NSMenu.popUpContextMenu(dropdown, with: event, for: button)
            } else {
                dropdown.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            }
            return
        }
        onClick?()
    }

    fileprivate static let iconSize: CGFloat = 20
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)

    private static func loadImage(sfSymbol: String?, path: String?, color: NSColor?) -> NSImage? {
        if let path, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                return Self.thumbnail(img, length: iconSize)
            }
        }
        guard let sfSymbol, !sfSymbol.isEmpty,
              let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil) else {
            return nil
        }
        var config = symbolConfig.applying(.preferringMonochrome())
        if let color {
            config = config.applying(.init(paletteColors: [color]))
        }
        let out = img.withSymbolConfiguration(config) ?? img
        out.size = NSSize(width: iconSize, height: iconSize)
        out.isTemplate = color == nil
        return out
    }

    private static func thumbnail(_ source: NSImage, length: CGFloat) -> NSImage {
        let size = NSSize(width: length, height: length)
        let out = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        out.isTemplate = false
        return out
    }

    static func parseColor(_ raw: String?) -> NSColor? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
            return NSColor(
                srgbRed: CGFloat((n >> 16) & 0xff) / 255,
                green: CGFloat((n >> 8) & 0xff) / 255,
                blue: CGFloat(n & 0xff) / 255,
                alpha: 1
            )
        }
        switch s.lowercased() {
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "gray", "grey": return .systemGray
        case "white": return .white
        case "black": return .labelColor
        default: return nil
        }
    }
}

enum StatusLineStyle {
    static func fontSize(twoLine: Bool, secondary: Bool, subtitle: Bool) -> CGFloat {
        if !twoLine { return 13 }
        if secondary && subtitle { return 9 }
        return 10
    }

    static func length(naturalWidth: CGFloat, minWidth: Double?) -> CGFloat? {
        minWidth.map { max(naturalWidth, CGFloat($0)) }
    }

    static func lines(
        title: String,
        subtitle: String?,
        color: NSColor?,
        subtitleColor: NSColor?,
        bold: Bool,
        italic: Bool,
        secondary: Bool
    ) -> [NSAttributedString] {
        let subtitle = subtitle ?? ""
        let twoLine = !subtitle.isEmpty
        var result: [NSAttributedString] = []
        if !title.isEmpty {
            result.append(NSAttributedString(
                string: title,
                attributes: [
                    .font: font(
                        size: fontSize(twoLine: twoLine, secondary: secondary, subtitle: false),
                        bold: bold,
                        italic: italic
                    ),
                    .foregroundColor: color ?? NSColor.labelColor,
                ]
            ))
        }
        if twoLine {
            result.append(NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: font(
                        size: fontSize(twoLine: true, secondary: secondary, subtitle: true),
                        bold: secondary ? false : bold,
                        italic: italic
                    ),
                    .foregroundColor: subtitleColor
                        ?? (secondary ? color?.withAlphaComponent(0.75) ?? .secondaryLabelColor : color ?? .labelColor),
                ]
            ))
        }
        return result
    }

    // Bottom-based y origin for each line, top line first. Lines stack from
    // the vertical center; when the stack is taller than the bar, the
    // inter-line gap goes negative, letting descender and ascender boxes
    // overlap (their ink rarely collides) instead of clipping at the edges.
    static func lineOrigins(barHeight: CGFloat, heights: [CGFloat]) -> [CGFloat] {
        let sum = heights.reduce(0, +)
        let gap = heights.count > 1 ? min(0, barHeight - 1 - sum) : 0
        let total = sum + gap * CGFloat(heights.count - 1)
        var y = barHeight - (barHeight - total) / 2
        return heights.map { h in
            y -= h
            defer { y -= gap }
            return y
        }
    }

    static let iconTextSpacing: CGFloat = 4

    @MainActor
    static func image(icon: NSImage?, lines: [NSAttributedString], height: CGFloat) -> NSImage {
        let textWidth = ceil(lines.map { $0.size().width }.max() ?? 0)
        let textX = icon.map { $0.size.width + iconTextSpacing } ?? 0
        let size = NSSize(width: textX + textWidth, height: height)
        let heights = lines.map { $0.size().height }
        let origins = lineOrigins(barHeight: height, heights: heights)
        return NSImage(size: size, flipped: false) { _ in
            if let icon {
                let iconRect = NSRect(
                    x: 0,
                    y: (height - icon.size.height) / 2,
                    width: icon.size.width,
                    height: icon.size.height
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
                if icon.isTemplate {
                    NSColor.labelColor.set()
                    iconRect.fill(using: .sourceAtop)
                }
            }
            for (line, y) in zip(lines, origins) {
                line.draw(at: NSPoint(x: textX, y: y))
            }
            return true
        }
    }

    private static func font(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = NSFont.menuBarFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        return font
    }
}

enum PluginMenu {
    final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func invoke(_ sender: Any?) { run() }
    }

    static func item(title: String, icon: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let icon {
            if icon.count <= 2 {
                item.title = "\(icon) \(title)"
            } else {
                item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            }
        }
        return item
    }

    static func make(_ entries: [MenuBarEntry], retaining boxes: inout [Action]) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            if entry.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let row = item(title: entry.title, icon: entry.icon)
            if !entry.children.isEmpty {
                row.submenu = make(entry.children, retaining: &boxes)
            } else if let onClick = entry.onClick {
                let box = Action(onClick)
                boxes.append(box)
                row.representedObject = box
                row.target = box
                row.action = #selector(Action.invoke)
            } else {
                row.isEnabled = false
            }
            menu.addItem(row)
        }
        return menu
    }
}
