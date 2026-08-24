import AppKit
import MacotronEngine

// HARD-WON RENDERING NOTES — read before changing how status items draw.
//
// NSStatusBarButton silently mangles several things we hand it, all
// diagnosed by snapshotting the live buttons (`cacheDisplay`) rather than
// trusting the APIs:
//
// 1. Multi-line attributed titles are NOT vertically centered. Pixel
//    measurements showed a two-line title block sitting ~4pt above the bar's
//    true center, so one edge always clipped. Paragraph-style tricks
//    (negative lineSpacing, maximumLineHeight caps, baselineOffset) only
//    move the clipping around. Single-line attributed titles have a related
//    flaw: the cell places the text cap-band ~1pt above the leading icon's
//    optical center, so icon+text items read as "text too high". Buttons DO
//    center images reliably, so ALL text (one or two lines) is drawn into a
//    single bar-height image (StatusLineStyle.image) with explicit line
//    layout; only icon-only items hand the button a bare image.
//
// 2. Symbol-backed NSImages (from NSImage(systemSymbolName:)) are re-laid
//    out with the button's own symbol configuration, vertically squashing
//    the glyph: a cup.and.saucer whose natural ink is 22x16pt drew at
//    20x11pt, which reads as "clipped". Mutating `.size` on a symbol image
//    is equally unsafe (it crops/distorts instead of scaling). The fix is
//    to rasterize the configured symbol into a handler-backed NSImage
//    (see loadImage); the button cannot reconfigure those. Handler images
//    still work as templates and redraw per-appearance, since the drawing
//    handler runs at display time — MenuBarIcon uses the same technique.
//
// 3. The composed image should be as tall as the actual bar, which on
//    notched Macs (30pt) is TALLER than NSStatusBar.system.thickness (22pt).
//    But `button.window.frame` is still zero during the FIRST apply — using
//    it directly baked zero-size images, collapsing rarely-repainting items
//    (audio, weather) to empty 16pt stubs while frequently-repainting ones
//    self-healed. apply() therefore falls back to thickness when the window
//    has no frame yet and schedules a short re-apply (scheduleReapply) until
//    layout has happened, so every item eventually composes at full height.
//
// Sizing and spacing decisions (tuned by eye against system items):
// - Menu bar icons live in an 18pt slot (MenuBarIcon); SF symbols at
//   pointSize 15/.medium match the visual scale of system status icons.
//   Larger images (the old 20pt/18pt combo) clip against the button's
//   vertical insets.
// - Two-line stacks use a fixed -1.5pt inter-line overlap (twoLineGap):
//   adjacent line boxes (gap 0) read too airy because each box carries
//   ascent/descent padding, while the -3pt squeeze from a 22pt compose
//   height was visibly cramped. Shorter bars squeeze further as needed.
// - Single-line text is geometrically centered as a line box, which lands
//   its cap-band on the leading icon's optical center — matching how the
//   system pairs icon and text.
//
@MainActor
final class PluginStatusItem: NSObject {
    let id: String
    private let item: NSStatusItem
    private var onClick: (() -> Void)?
    private var menuKeep: [PluginMenu.Action] = []
    private var dropdown: NSMenu?
    private var visibility: NSKeyValueObservation?
    private var removed = false

    /// Command-dragging an item out of the menu bar sets `isVisible` false and
    /// macOS remembers it, so the item stays gone across launches. Most plugins
    /// mean their item to be there, so say so; `required: false` opts out.
    var required = true
    var onVisibilityChange: ((String, Bool) -> Void)?

    var isVisible: Bool { item.isVisible }

    func restore() {
        item.isVisible = true
    }

    init(id: String) {
        self.id = id
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        visibility = item.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            let visible = item.isVisible
            DispatchQueue.main.async {
                guard let self else { return }
                self.onVisibilityChange?(self.id, visible)
            }
        }
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(clicked)
        // Menu bar buttons act on the press, not the release: waiting for
        // mouse-up is the "slight delay" every other item does not have.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
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
        reapplyWork?.cancel()
        self.onClick = onClick
        if menu.isEmpty {
            menuKeep.removeAll()
            dropdown = nil
        } else {
            let bar = dropdown ?? NSMenu()
            dropdown = bar
            PluginMenu.sync(bar, to: menu, retaining: &menuKeep)
        }
        // With no click handler the menu is the whole item, so hand it to
        // AppKit: it anchors under the icon, highlights the button, and opens
        // on the press. Doing it ourselves is what put the menu at the mouse.
        item.menu = onClick == nil ? dropdown : nil
        let button = item.button
        button?.target = self
        button?.action = #selector(clicked)
        // Plugins repaint on a timer whether or not anything moved, and the
        // work below -- rasterize, compose, re-measure the item -- is the
        // expensive half of a tick. Skip it when nothing would change.
        var signature = [
            title, subtitle ?? "", color ?? "", subtitleColor ?? "",
            "\(bold)\(italic)\(secondary)", "\(minWidth ?? -1)",
            sfSymbol ?? "", imagePath ?? "",
        ].joined(separator: "|")
        if let imagePath, let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath) {
            let stamp = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            signature += "|\(attrs[.size] as? Int ?? 0)@\(stamp)"
        }
        if signature == lastSignature { return }

        let nsColor = Self.parseColor(color)
        let nsSubtitleColor = Self.parseColor(subtitleColor)
        let iconOnly = title.isEmpty && (subtitle ?? "").isEmpty
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
        reapplyPending = false
        if iconOnly {
            button?.image = image
            button?.imagePosition = .imageOnly
        } else {
            // All text goes through the composed image (see rendering notes).
            // The bar can be taller than NSStatusBar.thickness (30pt vs 22pt
            // on notched Macs), but the window frame is still zero on the
            // first apply. Fall back to thickness then, and re-apply shortly
            // after so rarely-repainting items get the full-height layout.
            let windowHeight = button?.window?.frame.height ?? 0
            let height = windowHeight > 0 ? windowHeight : NSStatusBar.system.thickness
            if windowHeight <= 0 {
                reapplyPending = true
                scheduleReapply(
                    title: title, subtitle: subtitle, color: color,
                    subtitleColor: subtitleColor, bold: bold, italic: italic,
                    secondary: secondary, minWidth: minWidth, sfSymbol: sfSymbol,
                    imagePath: imagePath, onClick: onClick, menu: menu
                )
            }
            button?.image = StatusLineStyle.image(icon: image, lines: lines, height: height)
            button?.imagePosition = .imageOnly
        }
        button?.attributedTitle = NSAttributedString()
        let natural = ceil(button?.image?.size.width ?? 0)
        if natural > 0 || minWidth != nil {
            item.length = StatusLineStyle.length(naturalWidth: natural, minWidth: minWidth)
        } else {
            item.length = NSStatusItem.variableLength
        }
        button?.toolTip = subtitle.map { "\(title) — \($0)" } ?? title
        // A layout measured against a zero-height window is provisional, so
        // leave the door open for the reapply to redo it.
        lastSignature = reapplyPending ? nil : signature
    }

    private var lastSignature: String?
    private var reapplyPending = false
    private var reapplyWork: DispatchWorkItem?
    private var reapplyAttempts = 0

    private func scheduleReapply(
        title: String, subtitle: String?, color: String?, subtitleColor: String?,
        bold: Bool, italic: Bool, secondary: Bool, minWidth: Double?,
        sfSymbol: String?, imagePath: String?, onClick: (() -> Void)?,
        menu: [MenuBarEntry]
    ) {
        guard reapplyAttempts < 20, item.isVisible else { return }
        reapplyAttempts += 1
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.apply(
                title: title, subtitle: subtitle, color: color,
                subtitleColor: subtitleColor, bold: bold, italic: italic,
                secondary: secondary, minWidth: minWidth, sfSymbol: sfSymbol,
                imagePath: imagePath, onClick: onClick, menu: menu
            )
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func remove() {
        reapplyWork?.cancel()
        visibility?.invalidate()
        visibility = nil
        onVisibilityChange = nil
        // Removing an item twice raises, and a reload can race a removal.
        guard !removed else { return }
        removed = true
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        let event = item.button?.window?.currentEvent ?? NSApp.currentEvent
        let menuClick = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true
        if (menuClick || onClick == nil), let dropdown, let button = item.button {
            // Lend the menu to the status item for the length of the click so
            // AppKit places it, then take it back so the next left-click still
            // reaches onClick. performClick blocks until the menu closes.
            item.menu = dropdown
            button.performClick(nil)
            item.menu = nil
            return
        }
        onClick?()
    }

    // Match the menu bar's standard 18pt icon slot (see MenuBarIcon);
    // larger images clip against the status button's vertical insets.
    fileprivate static let iconSize: CGFloat = 18
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

    private static func loadImage(sfSymbol: String?, path: String?, color: NSColor?) -> NSImage? {
        if let path, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                // Same rule AppKit applies to bundled images: a file named
                // ...Template is a mask, and the bar tints it to suit itself.
                img.isTemplate = (expanded as NSString).deletingPathExtension.hasSuffix("Template")
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
        let configured = img.withSymbolConfiguration(config) ?? img
        // Rasterize: NSStatusBarButton re-applies its own symbol layout to
        // symbol-backed images, squashing the glyph into a shorter band.
        // A handler-backed image keeps our metrics and still tints as a
        // template, like MenuBarIcon.
        let out = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            return true
        }
        out.isTemplate = color == nil
        return out
    }

    private static func thumbnail(_ source: NSImage, length: CGFloat) -> NSImage {
        let src = source.size
        let aspect = src.height > 0 ? src.width / src.height : 1
        let size = NSSize(width: max(length * aspect, length), height: length)
        let out = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            return true
        }
        out.isTemplate = source.isTemplate
        return out
    }

    static func parseColor(_ raw: String?) -> NSColor? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { return HexColor.parse(s) }
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

    static func length(naturalWidth: CGFloat, minWidth: Double?) -> CGFloat {
        max(naturalWidth, CGFloat(minWidth ?? 0))
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
    // the vertical center with a slight overlap (line boxes include ascent
    // and descent padding, so adjacent boxes read too airy); when the stack
    // is taller than the bar, the gap goes further negative, letting
    // descender and ascender boxes overlap instead of clipping at the edges.
    static let twoLineGap: CGFloat = -1.5

    static func lineOrigins(barHeight: CGFloat, heights: [CGFloat]) -> [CGFloat] {
        let sum = heights.reduce(0, +)
        let gap = heights.count > 1 ? min(twoLineGap, barHeight - 1 - sum) : 0
        let total = sum + gap * CGFloat(heights.count - 1)
        var y = barHeight - (barHeight - total) / 2
        return heights.map { h in
            y -= h
            defer { y -= gap }
            return y
        }
    }

    static let iconTextSpacing: CGFloat = 5

    // SF Symbols ship on a padded canvas; layout from opaque ink so the
    // glyph sits closer to the pill edge and the title.
    static func inkFrame(_ image: NSImage) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSRect(origin: .zero, size: size)
        }
        let scale: CGFloat = 2
        let pixels = NSSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSRect(origin: .zero, size: size)
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return NSRect(origin: .zero, size: size) }
        let spp = rep.samplesPerPixel
        let rowBytes = rep.bytesPerRow
        let alphaSlot = spp - 1
        var minX = Int(pixels.width), minY = Int(pixels.height), maxX = 0, maxY = 0
        var found = false
        for y in 0..<Int(pixels.height) {
            let row = data + y * rowBytes
            for x in 0..<Int(pixels.width) {
                guard row[x * spp + alphaSlot] > 20 else { continue }
                found = true
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard found else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    @MainActor
    static func image(icon: NSImage?, lines: [NSAttributedString], height: CGFloat) -> NSImage {
        let textWidth = ceil(lines.map { $0.size().width }.max() ?? 0)
        let ink = icon.map(inkFrame)
        let textX = ink.map { $0.width + iconTextSpacing } ?? 0
        let size = NSSize(width: textX + textWidth, height: height)
        let heights = lines.map { $0.size().height }
        let origins = lineOrigins(barHeight: height, heights: heights)
        return NSImage(size: size, flipped: false) { _ in
            if let icon, let ink {
                let iconRect = NSRect(
                    x: -ink.origin.x,
                    y: (height - ink.height) / 2 - ink.origin.y,
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
        apply(title: title, icon: icon, to: item)
        return item
    }

    static func make(_ entries: [MenuBarEntry], retaining boxes: inout [Action]) -> NSMenu {
        let menu = NSMenu()
        append(entries, to: menu, retaining: &boxes)
        return menu
    }

    static func sync(_ menu: NSMenu, to entries: [MenuBarEntry], retaining boxes: inout [Action]) {
        boxes.removeAll()
        if sameShape(menu, entries) {
            write(entries, onto: menu, retaining: &boxes)
        } else {
            menu.removeAllItems()
            append(entries, to: menu, retaining: &boxes)
        }
    }

    /// Name stamped on the image so a repaint can tell whether the icon really
    /// changed. Prefixed so it cannot shadow a real named image.
    static func imageStamp(_ symbol: String) -> String { "macotron.menu.\(symbol)" }

    /// Symbol name for an icon, or nil when the icon is an emoji that belongs
    /// in the title instead.
    static func symbolName(_ icon: String?) -> String? {
        guard let icon, icon.count > 2 else { return nil }
        return icon
    }

    static func menuTitle(title: String, icon: String?) -> String {
        guard let icon, icon.count <= 2 else { return title }
        return "\(icon) \(title)"
    }

    static func apply(title: String, icon: String?, to item: NSMenuItem) {
        let text = menuTitle(title: title, icon: icon)
        if item.title != text { item.title = text }
        // Re-assigning the image of an item in an OPEN menu makes AppKit
        // re-measure the image column and nudge the text right, so a plugin
        // repainting every couple of seconds walks its row across the menu.
        // Only touch the image when the icon actually changed.
        let stamp = Self.symbolName(icon).map(imageStamp)
        guard item.image?.name() != stamp else { return }
        item.image = Self.symbolName(icon).flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }
        if let stamp { item.image?.setName(stamp) }
    }

    private static func sameShape(_ menu: NSMenu, _ entries: [MenuBarEntry]) -> Bool {
        guard menu.items.count == entries.count else { return false }
        return zip(menu.items, entries).allSatisfy { item, entry in
            if entry.isSeparator { return item.isSeparatorItem }
            if item.isSeparatorItem { return false }
            if (entry.html != nil) != (item.view is MenuWebView) { return false }
            if entry.children.isEmpty {
                return item.submenu == nil
            }
            guard let submenu = item.submenu else { return false }
            return sameShape(submenu, entry.children)
        }
    }

    private static func write(_ entries: [MenuBarEntry], onto menu: NSMenu, retaining boxes: inout [Action]) {
        for (item, entry) in zip(menu.items, entries) {
            if entry.isSeparator { continue }
            if let html = entry.html, let view = item.view as? MenuWebView {
                view.update(html: html, size: size(entry))
                continue
            }
            apply(title: entry.title, icon: entry.icon, to: item)
            if !entry.children.isEmpty, let submenu = item.submenu {
                write(entry.children, onto: submenu, retaining: &boxes)
            } else {
                bind(entry, to: item, retaining: &boxes)
            }
        }
    }

    private static func append(_ entries: [MenuBarEntry], to menu: NSMenu, retaining boxes: inout [Action]) {
        for entry in entries {
            if entry.isSeparator {
                menu.addItem(.separator())
                continue
            }
            if let html = entry.html {
                let row = NSMenuItem()
                row.view = MenuWebView(html: html, size: size(entry))
                menu.addItem(row)
                continue
            }
            let row = item(title: entry.title, icon: entry.icon)
            if !entry.children.isEmpty {
                row.submenu = make(entry.children, retaining: &boxes)
            } else {
                bind(entry, to: row, retaining: &boxes)
            }
            menu.addItem(row)
        }
    }

    static func size(_ entry: MenuBarEntry) -> NSSize {
        NSSize(
            width: max(60, min(entry.size.width, 800)),
            height: max(24, min(entry.size.height, 600))
        )
    }

    private static func bind(_ entry: MenuBarEntry, to item: NSMenuItem, retaining boxes: inout [Action]) {
        let box = Action(entry.onClick ?? {})
        boxes.append(box)
        item.representedObject = box
        item.target = box
        item.action = #selector(Action.invoke)
    }
}
