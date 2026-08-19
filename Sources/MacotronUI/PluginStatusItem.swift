import AppKit
import MacotronEngine

@MainActor
final class PluginStatusItem: NSObject {
    let id: String
    private let item: NSStatusItem
    private let host = StatusHostView()
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
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.required, for: .horizontal)
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            host.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor),
            host.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor),
        ])
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
        let image = Self.loadImage(sfSymbol: sfSymbol, path: imagePath, color: iconOnly ? nsColor : nil)
        button?.image = nil
        button?.contentTintColor = nil
        host.isHidden = false
        host.configure(
            title: title,
            subtitle: subtitle,
            color: nsColor,
            subtitleColor: nsSubtitleColor,
            bold: bold,
            italic: italic,
            secondary: secondary,
            image: image
        )
        host.invalidateIntrinsicContentSize()
        host.layoutSubtreeIfNeeded()
        // 4pt insets on each side plus a little for glyph overhang.
        let fitted = ceil(host.fittingSize.width) + 10
        item.length = max(fitted, CGFloat(minWidth ?? 0))
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
}

private final class StatusHostView: NSView {
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private let root = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.clipsToBounds = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerCurve = .continuous
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)

        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        subtitleField.usesSingleLineMode = true
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = -1
        textStack.addArrangedSubview(titleField)
        textStack.addArrangedSubview(subtitleField)

        root.orientation = .horizontal
        root.alignment = .centerY
        root.spacing = 4
        root.addArrangedSubview(imageView)
        root.addArrangedSubview(textStack)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: PluginStatusItem.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: PluginStatusItem.iconSize),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        clipsToBounds = true
        layer?.masksToBounds = true
        imageView.layer?.masksToBounds = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(title: String, subtitle: String?, color: NSColor?, subtitleColor: NSColor?, bold: Bool, italic: Bool, secondary: Bool, image: NSImage?) {
        let hasTitle = !title.isEmpty
        let twoLine = !(subtitle ?? "").isEmpty
        titleField.stringValue = title
        titleField.isHidden = !hasTitle
        titleField.font = Self.font(size: StatusLineStyle.fontSize(twoLine: twoLine, secondary: secondary, subtitle: false), bold: bold, italic: italic)
        titleField.textColor = color ?? .labelColor
        subtitleField.stringValue = subtitle ?? ""
        subtitleField.isHidden = !twoLine
        subtitleField.font = Self.font(
            size: StatusLineStyle.fontSize(twoLine: twoLine, secondary: secondary, subtitle: true),
            bold: secondary ? false : bold,
            italic: italic
        )
        if let subtitleColor {
            subtitleField.textColor = subtitleColor
        } else if secondary {
            subtitleField.textColor = color?.withAlphaComponent(0.75) ?? .secondaryLabelColor
        } else {
            subtitleField.textColor = color ?? .labelColor
        }
        textStack.isHidden = !hasTitle && !twoLine
        imageView.image = image
        imageView.isHidden = image == nil
        imageView.contentTintColor = image?.isTemplate == true ? .labelColor : nil
        imageView.layer?.cornerRadius = image?.isTemplate == false ? 4 : 0
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        root.fittingSize
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
