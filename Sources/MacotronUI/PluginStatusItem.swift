import AppKit
import MacotronEngine

@MainActor
final class PluginStatusItem: NSObject {
    let id: String
    private let item: NSStatusItem
    private let host = StatusHostView()
    private var onClick: (() -> Void)?
    private var menuKeep: [PluginMenu.Action] = []

    init(id: String) {
        self.id = id
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        guard let button = item.button else { return }
        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(clicked)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    func apply(
        title: String,
        subtitle: String?,
        color: String?,
        bold: Bool,
        italic: Bool,
        sfSymbol: String?,
        imagePath: String?,
        onClick: (() -> Void)?,
        menu: [MenuBarEntry] = []
    ) {
        self.onClick = onClick
        menuKeep.removeAll()
        if menu.isEmpty {
            item.menu = nil
            item.button?.target = self
            item.button?.action = #selector(clicked)
        } else {
            item.menu = PluginMenu.make(menu, retaining: &menuKeep)
            item.button?.target = nil
            item.button?.action = nil
        }
        let nsColor = Self.parseColor(color)
        let image = Self.loadImage(sfSymbol: sfSymbol, path: imagePath, color: nsColor)
        host.configure(
            title: title,
            subtitle: subtitle,
            color: nsColor,
            bold: bold,
            italic: italic,
            image: image
        )
        host.layoutSubtreeIfNeeded()
        item.length = max(host.fittingSize.width + 10, 18)
        item.button?.toolTip = subtitle.map { "\(title) — \($0)" } ?? title
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func clicked() {
        onClick?()
    }

    private static func loadImage(sfSymbol: String?, path: String?, color: NSColor?) -> NSImage? {
        if let path, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) {
                img.size = NSSize(width: 16, height: 16)
                img.isTemplate = color == nil
                return img
            }
        }
        guard let sfSymbol, !sfSymbol.isEmpty,
              let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil) else {
            return nil
        }
        if let color {
            img.isTemplate = false
            return img.withSymbolConfiguration(.init(paletteColors: [color])) ?? img
        }
        img.isTemplate = true
        return img
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

private final class StatusHostView: NSView {
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private let root = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1

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
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(title: String, subtitle: String?, color: NSColor?, bold: Bool, italic: Bool, image: NSImage?) {
        let twoLine = !(subtitle ?? "").isEmpty
        titleField.stringValue = title
        titleField.font = Self.font(size: twoLine ? 10 : 13, bold: bold, italic: italic)
        titleField.textColor = color ?? .labelColor
        subtitleField.stringValue = subtitle ?? ""
        subtitleField.isHidden = !twoLine
        subtitleField.font = Self.font(size: 9, bold: false, italic: italic)
        subtitleField.textColor = color?.withAlphaComponent(0.75) ?? .secondaryLabelColor
        imageView.image = image
        imageView.isHidden = image == nil
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
                row.target = box
                row.action = #selector(Action.invoke)
            }
            menu.addItem(row)
        }
        return menu
    }
}
