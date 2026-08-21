// LauncherPanel.swift — Floating NSPanel for the launcher
import AppKit

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
    private let windowFrame: LauncherFrame
    private var lastHeight: CGFloat = LauncherPlacement.minHeight
    public var onHide: (() -> Void)?
    private var isOrderingOut = false
    /// Nonactivating panels can resign key on the same turn they become key.
    private var dismissOnResign = false

    public init(contentView: NSView, windowFrame: LauncherFrame) {
        hostingView = contentView
        self.windowFrame = windowFrame
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
        isMovable = false
        applySizeLimits(in: seed, height: Self.minHeight)
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        worksWhenModal = true
        applyBackground(.translucent)
        self.delegate = self
    }

    public func applyBackground(_ style: LauncherBackground) {
        hostingView.removeFromSuperview()
        if #available(macOS 26.0, *) {
            Self.glass(in: contentView)?.contentView = nil
        }
        let visible = currentVisible
        let height = isShown ? lastHeight : Self.minHeight
        let width = LauncherPlacement.width(in: visible)
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
        invalidateShadow()
        if isShown {
            resizeToHeight(lastHeight)
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
            visual.maskImage = cornerMask(radius: cornerRadius)
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

    /// Corner shape for behind-window vibrancy.
    ///
    /// The window server blurs and shadows a behind-window effect view using its
    /// mask image; CALayer corner masking is invisible to it. Without a mask the
    /// shadow is cast from the panel's square frame, so the transparent corners
    /// land on unshadowed backdrop and read as bright notches over flat, light
    /// windows. Cap insets keep the corners fixed as the panel resizes.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    @available(macOS 26.0, *)
    private static func glass(in view: NSView?) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView { return glass }
        return view?.subviews.first as? NSGlassEffectView
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Queue a resize for the next run loop turn.
    ///
    /// Content height changes arrive from SwiftUI while AppKit is still inside
    /// the search field's text-change processing. Resizing the window there
    /// leaves the content view, its clip view, and the hosting view holding a
    /// mix of old and new geometry, which is what pushes the search field off
    /// the top. Deferring puts the resize on a settled layout, and coalescing
    /// collapses a burst of keystrokes into one resize.
    public func requestHeight(_ height: CGFloat) {
        pendingHeight = height
        guard !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            guard let height = self.pendingHeight else { return }
            self.pendingHeight = nil
            self.resizeToHeight(height)
        }
    }

    private var pendingHeight: CGFloat?
    private var resizeScheduled = false

    /// Size the window to content. SwiftUI is told that size first so only the
    /// results list can overflow, like overflow-y: auto on that section.
    public func resizeToHeight(_ height: CGFloat) {
        let visible = currentVisible
        let pin = isShown ? frame.maxY : nil
        let newFrame = LauncherPlacement.frame(height: height, visible: visible, pinTop: pin)
        applySizeLimits(in: visible, height: newFrame.height)
        lastHeight = newFrame.height
        windowFrame.size = newFrame.size
        if abs(frame.width - newFrame.width) < 0.5 && abs(frame.height - newFrame.height) < 0.5
            && abs(frame.origin.x - newFrame.origin.x) < 0.5 && abs(frame.origin.y - newFrame.origin.y) < 0.5 {
            pinHost()
            return
        }
        setFrame(newFrame, display: true)
        pinHost()
    }

    private func reveal() {
        alphaValue = 1
        dismissOnResign = false
        orderFrontRegardless()
        makeKey()
        if let textField = contentView?.firstEditableTextField() {
            makeFirstResponder(textField)
        }
        isShown = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissOnResign = true
            if self.isShown && self.isVisible && !self.isKeyWindow {
                self.orderOut(nil)
            }
        }
    }

    public override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible || isShown
        pendingHeight = nil
        isOrderingOut = true
        super.orderOut(sender)
        isOrderingOut = false
        isShown = false
        dismissOnResign = false
        if wasVisible {
            onHide?()
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    /// True once the panel is fully shown, so the resign-key handler ignores the
    /// transient key changes that happen while it is still being revealed.
    private var isShown = false

    public func dismiss() {
        guard isVisible || isShown else { return }
        orderOut(nil)
    }

    public func toggle() {
        if isVisible {
            dismiss()
        } else {
            pendingHeight = nil
            resizeToHeight(lastHeight)
            reveal()
        }
    }

    /// The shadow is cached from the panel's shape, so a resize leaves it drawn
    /// around the old bounds until it is invalidated.
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        applyingFrame = true
        super.setFrame(frameRect, display: flag)
        applyingFrame = false
        windowFrame.size = frame.size
        pinHost()
        invalidateShadow()
    }

    private func pinHost() {
        guard let parent = hostingView.superview else { return }
        hostingView.frame = parent.bounds
    }

    public override func setContentSize(_ size: NSSize) {
        guard applyingFrame else { return }
        super.setContentSize(size)
    }

    private var applyingFrame = false

    private var currentVisible: CGRect { LauncherPlacement.currentVisible() }

    private func applySizeLimits(in visible: CGRect, height: CGFloat) {
        let width = LauncherPlacement.width(in: visible)
        let size = NSSize(width: width, height: height)
        minSize = size
        maxSize = size
    }

}

extension LauncherPanel: NSWindowDelegate {
    /// Dismiss when the launcher loses key focus — clicking another app or
    /// window, or switching away. This replaces the activation-based auto-hide
    /// that was racing with the global hotkey.
    public func windowDidResignKey(_ notification: Notification) {
        guard isShown, isVisible, !isOrderingOut, dismissOnResign else { return }
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
