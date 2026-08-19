// LauncherPanel.swift — Floating NSPanel for the launcher
import AppKit
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "launcher")

private extension NSView {
    func firstEditableTextField() -> NSTextField? {
        if let tf = self as? NSTextField, tf.isEditable { return tf }
        for subview in subviews {
            if let found = subview.firstEditableTextField() { return found }
        }
        return nil
    }
}

@MainActor
public final class LauncherPanel: NSPanel {
    private static let minHeight: CGFloat = LauncherPlacement.minHeight
    private static let cornerRadius: CGFloat = 12

    private let hostingView: NSView
    /// Cached content height from the last layout pass — used to open at the right size.
    private var lastContentHeight: CGFloat = 0
    public var onHide: (() -> Void)?
    /// App that was frontmost before we activated, so Escape can give typing back.
    private var appToRestore: NSRunningApplication?
    private var shouldRestoreApp = false
    private var isOrderingOut = false

    public init(contentView: NSView) {
        hostingView = contentView
        let seed = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let seedWidth = LauncherPlacement.width(in: seed)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: seedWidth, height: Self.minHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        applySizeLimits(in: seed, height: Self.minHeight)
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        applyBackground(.translucent)
        self.delegate = self
    }

    public func applyBackground(_ style: LauncherBackground) {
        hostingView.removeFromSuperview()
        if #available(macOS 26.0, *) {
            Self.glass(in: contentView)?.contentView = nil
        }
        let height = lastContentHeight > 0 ? lastContentHeight : Self.minHeight
        let width = LauncherPlacement.width(in: currentVisible)
        let chrome = Self.makeChrome(style, size: NSSize(width: width, height: height))
        let pin = HostPinView(frame: chrome.bounds)
        pin.autoresizingMask = [.width, .height]
        pin.wantsLayer = true
        pin.layer?.masksToBounds = true
        hostingView.frame = pin.bounds
        hostingView.autoresizingMask = [.width, .height]
        pin.addSubview(hostingView)
        if #available(macOS 26.0, *), let glass = Self.glass(in: chrome) {
            glass.contentView = pin
        } else {
            chrome.addSubview(pin)
        }
        contentView = chrome
        hasShadow = style != .glass
        if lastContentHeight > 0 {
            resizeToHeight(lastContentHeight)
        }
    }

    private static func makeChrome(_ style: LauncherBackground, size: NSSize) -> NSView {
        let frame = NSRect(origin: .zero, size: size)
        switch style {
        case .glass:
            if #available(macOS 26.0, *) {
                let clip = NSView(frame: frame)
                clip.wantsLayer = true
                clip.layer?.cornerRadius = cornerRadius
                clip.layer?.masksToBounds = true
                clip.autoresizingMask = [.width, .height]
                let glass = NSGlassEffectView(frame: clip.bounds)
                glass.style = .regular
                glass.cornerRadius = cornerRadius
                glass.clipsToBounds = true
                glass.autoresizingMask = [.width, .height]
                clip.addSubview(glass)
                return clip
            }
            fallthrough
        case .translucent:
            let visual = NSVisualEffectView(frame: frame)
            visual.material = .hudWindow
            visual.state = .active
            visual.blendingMode = .behindWindow
            visual.wantsLayer = true
            visual.layer?.cornerRadius = cornerRadius
            visual.layer?.masksToBounds = true
            visual.autoresizingMask = [.width, .height]
            return visual
        case .opaque:
            let view = OpaqueLauncherChrome(frame: frame)
            view.autoresizingMask = [.width, .height]
            return view
        }
    }

    @available(macOS 26.0, *)
    private static func glass(in view: NSView?) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView { return glass }
        return view?.subviews.first as? NSGlassEffectView
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Resize the panel to fit the given content height, keeping the top edge pinned.
    public func resizeToHeight(_ height: CGFloat) {
        let visible = currentVisible
        let newFrame = LauncherPlacement.frame(height: height, visible: visible, pinTop: nil)
        applySizeLimits(in: visible, height: newFrame.height)
        logPlacement("resize", height: height, visible: visible, pinTop: nil, frame: newFrame)
        lastContentHeight = newFrame.height
        guard abs(frame.height - newFrame.height) > 1 || abs(frame.origin.y - newFrame.origin.y) > 1
            || abs(frame.origin.x - newFrame.origin.x) > 1
            || abs(frame.width - newFrame.width) > 1 else {
            pinHost()
            return
        }
        setFrame(newFrame, display: true)
        pinHost()
        logger.notice("after \(NSStringFromRect(self.frame), privacy: .public) host=\(NSStringFromRect(self.hostingView.frame), privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pinHost()
            logger.notice("async \(NSStringFromRect(self.frame), privacy: .public) host=\(NSStringFromRect(self.hostingView.frame), privacy: .public)")
        }
    }

    private func reveal() {
        alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if let textField = contentView?.firstEditableTextField() {
            makeFirstResponder(textField)
        }
        isShown = true
    }

    public override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible || isShown
        isOrderingOut = true
        super.orderOut(sender)
        isOrderingOut = false
        isShown = false
        if wasVisible {
            lastContentHeight = Self.minHeight
            onHide?()
            restoreFrontAppIfNeeded()
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    /// True once the panel is fully shown, so the resign-key handler ignores the
    /// transient key changes that happen while it is still being revealed.
    private var isShown = false

    /// Hide the launcher. Escape restores the previous app; choosing a result does not.
    public func dismiss(restoreFrontApp: Bool = false) {
        shouldRestoreApp = restoreFrontApp
        guard isVisible || isShown else { return }
        orderOut(nil)
    }

    public func toggle() {
        if isVisible {
            dismiss(restoreFrontApp: true)
        } else {
            captureFrontApp()
            let height = lastContentHeight > 0 ? lastContentHeight : Self.minHeight
            let visible = currentVisible
            let newFrame = LauncherPlacement.frame(height: height, visible: visible, pinTop: nil)
            applySizeLimits(in: visible, height: newFrame.height)
            logPlacement("open", height: height, visible: visible, pinTop: nil, frame: newFrame)
            setFrame(newFrame, display: false)
            pinHost()
            logger.notice("after-open \(NSStringFromRect(self.frame), privacy: .public) host=\(NSStringFromRect(self.hostingView.frame), privacy: .public)")
            reveal()
        }
    }

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        pinHost()
    }

    private func pinHost() {
        guard let parent = hostingView.superview else { return }
        hostingView.frame = parent.bounds
    }

    public override func setContentSize(_ size: NSSize) {}

    private var currentVisible: CGRect { LauncherPlacement.currentVisible() }

    private func applySizeLimits(in visible: CGRect, height: CGFloat) {
        let width = LauncherPlacement.width(in: visible)
        let h = max(Self.minHeight, height)
        minSize = NSSize(width: width, height: h)
        maxSize = NSSize(width: width, height: h)
    }

    private func logPlacement(_ reason: String, height: CGFloat, visible: CGRect, pinTop: CGFloat?, frame: CGRect) {
        let topPct = visible.height > 0 ? (visible.maxY - frame.maxY) / visible.height : 0
        let widthPct = visible.width > 0 ? frame.width / visible.width : 0
        let heightPct = visible.height > 0 ? frame.height / visible.height : 0
        logger.notice("""
            launcher \(reason, privacy: .public) \
            wantH=\(height, format: .fixed(precision: 1), privacy: .public) \
            pin=\(pinTop.map { String(format: "%.1f", $0) } ?? "nil", privacy: .public) \
            current=\(NSStringFromRect(self.frame), privacy: .public) \
            visible=\(NSStringFromRect(visible), privacy: .public) \
            frame=\(NSStringFromRect(frame), privacy: .public) \
            topPct=\(topPct, format: .fixed(precision: 3), privacy: .public) \
            widthPct=\(widthPct, format: .fixed(precision: 3), privacy: .public) \
            heightPct=\(heightPct, format: .fixed(precision: 3), privacy: .public) \
            screen=\(self.screen?.localizedName ?? "none", privacy: .public)
            """)
    }

    private func captureFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != NSRunningApplication.current.processIdentifier {
            appToRestore = front
        } else {
            appToRestore = nil
        }
    }

    private func restoreFrontAppIfNeeded() {
        defer {
            shouldRestoreApp = false
            appToRestore = nil
        }
        guard shouldRestoreApp, let app = appToRestore, !app.isTerminated else { return }
        NSApp.yieldActivation(to: app)
        _ = app.activate()
    }
}

extension LauncherPanel: NSWindowDelegate {
    /// Dismiss when the launcher loses key focus — clicking another app or
    /// window, or switching away. This replaces the activation-based auto-hide
    /// that was racing with the global hotkey.
    public func windowDidResignKey(_ notification: Notification) {
        guard isShown, isVisible, !isOrderingOut else { return }
        shouldRestoreApp = false
        orderOut(nil)
    }
}

private final class HostPinView: NSView {
    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }
}

private final class OpaqueLauncherChrome: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        paint()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        paint()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}
