// ToastHost.swift — one-line HUD
import AppKit

enum ToastPosition: Equatable {
    case top
    case bottom

    static func parse(_ value: String?) -> ToastPosition {
        value?.lowercased() == "top" ? .top : .bottom
    }
}

enum ToastLayout {
    static let maxWidth: CGFloat = 420
    static let minWidth: CGFloat = 120
    static let minHeight: CGFloat = 36
    static let margin: CGFloat = 24

    static func line(_ title: String, _ body: String?) -> String {
        let extra = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return extra.isEmpty ? title : "\(title) \(extra)"
    }

    static func parseColor(_ raw: String?) -> NSColor? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
            return NSColor(
                srgbRed: CGFloat((n >> 16) & 0xff) / 255,
                green: CGFloat((n >> 8) & 0xff) / 255,
                blue: CGFloat(n & 0xff) / 255,
                alpha: 1
            )
        }
        switch s.lowercased() {
        case "success", "green": return .systemGreen
        case "failure", "error", "red": return .systemRed
        case "warning", "orange": return .systemOrange
        case "blue": return .systemBlue
        case "yellow": return .systemYellow
        default: return nil
        }
    }

    static func frame(size: NSSize, in anchor: NSRect, position: ToastPosition, margin: CGFloat = margin) -> NSRect {
        let maxW = max(minWidth, anchor.width - margin * 2)
        let width = min(max(size.width, minWidth), min(maxWidth, maxW))
        let height = max(size.height, minHeight)
        var x = anchor.midX - width / 2
        let minX = anchor.minX + margin
        let maxX = anchor.maxX - width - margin
        if maxX >= minX { x = min(max(x, minX), maxX) }
        let y = position == .top
            ? anchor.maxY - height - margin
            : anchor.minY + margin
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

enum ToastAnchor {
    static func rect() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ToastHost {
    static let shared = ToastHost()

    private var panel: NSPanel?
    private var titleField: NSTextField?
    private var iconView: NSImageView?
    private var row: NSStackView?
    private var hideWork: DispatchWorkItem?

    func show(title: String, body: String?, position: ToastPosition, duration: TimeInterval, sfSymbol: String? = nil, color: String? = nil) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        titleField?.stringValue = ToastLayout.line(title, body)
        var symbol = sfSymbol
        if symbol == nil, color?.lowercased() == "success" {
            symbol = "checkmark.circle.fill"
        }
        applyIcon(sfSymbol: symbol, color: color)
        layoutAndPlace(panel, position: position)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.usesSingleLineMode = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField = title

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isHidden = true
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        iconView = icon

        let row = NSStackView(views: [icon, title])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        self.row = row

        let panel = ToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = wrapGlass(row)
        return panel
    }

    private func applyIcon(sfSymbol: String?, color: String?) {
        guard let iconView else { return }
        guard let sfSymbol, let image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil) else {
            iconView.isHidden = true
            iconView.image = nil
            return
        }
        iconView.isHidden = false
        iconView.contentTintColor = ToastLayout.parseColor(color) ?? .labelColor
        iconView.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        iconView.image = image
    }

    private func wrapGlass(_ stack: NSStackView) -> NSView {
        let box = NSView(frame: .zero)
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = 18
            glass.contentView = box
            return glass
        }
        let visual = NSVisualEffectView(frame: .zero)
        visual.material = .hudWindow
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 18
        visual.layer?.masksToBounds = true
        visual.addSubview(box)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            box.topAnchor.constraint(equalTo: visual.topAnchor),
            box.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
        ])
        return visual
    }

    private func layoutAndPlace(_ panel: NSPanel, position: ToastPosition) {
        let anchor = ToastAnchor.rect()
        titleField?.preferredMaxLayoutWidth = min(
            ToastLayout.maxWidth - 48,
            max(80, anchor.width - ToastLayout.margin * 2 - 48)
        )
        row?.layoutSubtreeIfNeeded()
        var size = row?.fittingSize ?? NSSize(width: 120, height: 36)
        size.width = min(max(size.width, ToastLayout.minWidth), ToastLayout.maxWidth)
        size.height = max(size.height, ToastLayout.minHeight)
        panel.setFrame(ToastLayout.frame(size: size, in: anchor, position: position), display: true)
    }
}
