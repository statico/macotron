// ToastHost.swift — HUD toast. Text wraps; the panel grows with the copy.
import AppKit
import MacotronEngine

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
    static let minHeight: CGFloat = 40
    static let margin: CGFloat = 48

    enum Kind: Equatable {
        case info
        case success
        case error
        case warning
        case custom(NSColor)

        var tint: NSColor? {
            switch self {
            case .info: return nil
            case .success: return .systemGreen
            case .error: return .systemRed
            case .warning: return .systemOrange
            case .custom(let color): return color
            }
        }

        /// Semantic kinds color the text as part of the message. A custom
        /// color is data — a picked pixel, a brand color — and an arbitrary
        /// color over the toast background is unreadable, so it tints only
        /// the icon and the text stays legible.
        var textTint: NSColor? {
            if case .custom = self { return nil }
            return tint
        }

        var defaultSymbol: String? {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info, .custom: return nil
            }
        }
    }

    static func line(_ title: String, _ body: String?) -> String {
        let extra = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return extra.isEmpty ? title : "\(title) \(extra)"
    }

    static func kind(_ raw: String?) -> Kind {
        guard let raw else { return .info }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch s.lowercased() {
        case "", "info": return .info
        case "success", "green": return .success
        case "failure", "error", "red": return .error
        case "warning", "orange": return .warning
        default:
            return HexColor.parse(s).map { .custom($0) } ?? namedColor(s).map { .custom($0) } ?? .info
        }
    }

    private static func namedColor(_ s: String) -> NSColor? {
        switch s.lowercased() {
        case "blue": return .systemBlue
        case "yellow": return .systemYellow
        default: return nil
        }
    }

    static func frame(size: NSSize, in anchor: NSRect, position: ToastPosition, margin: CGFloat = margin) -> NSRect {
        let inner = max(0, anchor.width - margin * 2)
        let width = min(max(size.width, minWidth), min(maxWidth, inner > 0 ? inner : minWidth))
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
public final class ToastHost {
    public static let shared = ToastHost()

    /// Host-side one-liner: bottom toast with the standard duration.
    public func flash(_ text: String) {
        show(title: text, body: nil, position: .bottom, duration: 2)
    }

    /// Host-side warning: orange triangle, long enough to read twice.
    public func warn(_ title: String, _ body: String? = nil) {
        show(title: title, body: body, position: .bottom, duration: 5, color: "warning")
    }

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
        let kind = ToastLayout.kind(color)
        titleField?.textColor = kind.textTint ?? .labelColor
        applyIcon(sfSymbol: sfSymbol ?? kind.defaultSymbol, tint: kind.tint)
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
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.alignment = .center
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 0
        title.usesSingleLineMode = false
        title.cell?.wraps = true
        title.cell?.isScrollable = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField = title

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isHidden = true
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
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

    private func applyIcon(sfSymbol: String?, tint: NSColor?) {
        guard let iconView else { return }
        guard let sfSymbol, let image = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil) else {
            iconView.isHidden = true
            iconView.image = nil
            return
        }
        iconView.isHidden = false
        iconView.contentTintColor = tint ?? .labelColor
        iconView.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
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
        var size = row?.fittingSize ?? NSSize(width: 120, height: 40)
        size.width = min(max(size.width, ToastLayout.minWidth), ToastLayout.maxWidth)
        size.height = max(size.height, ToastLayout.minHeight)
        panel.setFrame(ToastLayout.frame(size: size, in: anchor, position: position), display: true)
    }
}
