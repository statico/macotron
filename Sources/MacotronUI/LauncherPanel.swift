// LauncherPanel.swift — Floating NSPanel for the launcher
import AppKit
import SwiftUI
import MacotronEngine

private extension NSView {
    func firstEditableTextField() -> NSTextField? {
        if let tf = self as? NSTextField, tf.isEditable { return tf }
        for subview in subviews {
            if let found = subview.firstEditableTextField() { return found }
        }
        return nil
    }
}

/// Shared dismiss machinery for the borderless nonactivating panels.
///
/// A nonactivating panel can resign key on the same turn it becomes key, so
/// resign-key dismissal is only armed a run loop turn after the panel is shown.
@MainActor
public class NonactivatingPanel: NSPanel, NSWindowDelegate {
    /// True once the panel is fully shown, so the resign-key handler ignores the
    /// transient key changes that happen while it is still being revealed.
    var isShown = false
    private var isOrderingOut = false
    var dismissOnResign = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// The panel flags both launcher and overlay share; shadow and modal
    /// behaviour stay with the caller.
    func configureFloatingPanel() {
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        delegate = self
    }

    /// Arm resign-key dismissal on the next run loop turn, and close the panel
    /// if it never took key focus.
    func armDismissOnResign(then extra: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissOnResign = true
            extra?()
            if self.isShown && self.isVisible && !self.isKeyWindow {
                self.orderOut(nil)
            }
        }
    }

    public override func orderOut(_ sender: Any?) {
        isOrderingOut = true
        super.orderOut(sender)
        isOrderingOut = false
        isShown = false
        dismissOnResign = false
    }

    /// How the panel goes away when it loses key focus; the launcher animates.
    func dismissOnFocusLoss() { orderOut(nil) }

    public func windowDidResignKey(_ notification: Notification) {
        guard isShown, isVisible, !isOrderingOut, dismissOnResign else { return }
        dismissOnFocusLoss()
    }
}

@MainActor
public final class LauncherPanel: NonactivatingPanel {
    private static let minHeight: CGFloat = LauncherPlacement.minHeight
    static let cornerRadius: CGFloat = 12
    private static let shadowPadding: CGFloat = LauncherPlacement.shadowPadding
    private static let showDuration: TimeInterval = 0.06
    private static let hideDuration: TimeInterval = 0.05

    private let hostingView: NSView
    private let windowFrame: LauncherFrame
    private var lastHeight: CGFloat = LauncherPlacement.minHeight
    public var onHide: (() -> Void)?

    public init(contentView: NSView, windowFrame: LauncherFrame) {
        hostingView = contentView
        self.windowFrame = windowFrame
        let seed = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let seedWidth = LauncherPlacement.width(in: seed)
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: seedWidth + 2 * Self.shadowPadding,
                height: Self.minHeight + 2 * Self.shadowPadding
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureFloatingPanel()
        // The panel draws its own shadow; see ShadowContainerView.
        hasShadow = false
        worksWhenModal = true
        applySizeLimits(in: seed, height: Self.minHeight)
        applyBackground(.translucent)
    }

    public func applyBackground(_ style: LauncherBackground) {
        hostingView.removeFromSuperview()
        if #available(macOS 26.0, *) {
            Self.glass(in: (contentView as? ShadowContainerView)?.chrome)?.contentView = nil
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
        let container = ShadowContainerView(
            chrome: chrome,
            padding: Self.shadowPadding,
            cornerRadius: Self.cornerRadius
        )
        // Glass brings its own shadow.
        container.drawsShadow = style != .glass
        contentView = container
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
                clip.layer?.cornerCurve = .continuous
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
            visual.layer?.cornerCurve = .continuous
            visual.layer?.masksToBounds = true
            visual.autoresizingMask = [.width, .height]
            let tint = PaintedView(frame: visual.bounds) { $0.layer?.backgroundColor = launcherTint.cgColor }
            tint.autoresizingMask = [.width, .height]
            visual.addSubview(tint)
            return visual
        case .opaque:
            let view = PaintedView(frame: frame) {
                $0.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
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
    ///
    /// The corners are squircles, which `NSBezierPath` cannot draw; SwiftUI's
    /// continuous rounded rectangle is the shortest way to the same curve that
    /// `cornerCurve` gives the layers.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let renderer = ImageRenderer(
            content: RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.black)
                .frame(width: side, height: side)
        )
        renderer.scale = 2
        let mask = renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    @available(macOS 26.0, *)
    private static func glass(in view: NSView?) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView { return glass }
        return view?.subviews.first as? NSGlassEffectView
    }

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
        let pad = Self.shadowPadding
        let pin = isShown ? frame.maxY - pad : nil
        let content = LauncherPlacement.frame(height: height, visible: visible, pinTop: pin)
        applySizeLimits(in: visible, height: content.height)
        lastHeight = content.height
        windowFrame.size = content.size
        let newFrame = content.insetBy(dx: -pad, dy: -pad)
        if abs(frame.width - newFrame.width) < 0.5 && abs(frame.height - newFrame.height) < 0.5
            && abs(frame.origin.x - newFrame.origin.x) < 0.5 && abs(frame.origin.y - newFrame.origin.y) < 0.5 {
            pinHost()
            return
        }
        setFrame(newFrame, display: true)
        pinHost()
    }

    /// Why the launcher is being shown, for the activation log.
    public var showReason: String = "unknown"

    /// Fade in instead of blinking on. Only the alpha moves: animating the
    /// window frame traps inside Combine, because `setFrame` publishes the
    /// content size and that store does not survive the animator proxy.
    private func reveal() {
        AppActivation.note("launcher shown: \(showReason)")
        isDismissing = false
        dismissOnResign = false
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        focusQueryField()
        isShown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        armDismissOnResign { [weak self] in self?.focusQueryField() }
    }

    /// Put the caret in the search field.
    ///
    /// On the first show after launch SwiftUI has not built its NSViews yet, so
    /// the field does not exist to focus. A layout pass materialises it; the
    /// retry from reveal's async block covers the case where it still hasn't.
    private func focusQueryField() {
        contentView?.layoutSubtreeIfNeeded()
        guard let field = contentView?.firstEditableTextField() else { return }
        guard firstResponder !== field, (firstResponder as? NSTextView)?.delegate !== field else { return }
        makeFirstResponder(field)
    }

    public override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible || isShown
        pendingHeight = nil
        isDismissing = false
        super.orderOut(sender)
        if wasVisible {
            onHide?()
        }
    }

    /// Dismiss on Escape key
    public override func cancelOperation(_ sender: Any?) {
        toggle()
    }

    /// True while the hide animation is running: the panel is still on screen
    /// but is already logically closed.
    private var isDismissing = false

    /// Hide the panel. Animated dismissals hold key focus for the length of the
    /// fade, so callers that hand focus to another app — running a command,
    /// revealing in Finder, opening settings — keep the instant path.
    public func dismiss(animated: Bool = false) {
        guard isVisible || isShown else { return }
        guard animated else {
            orderOut(nil)
            return
        }
        guard !isDismissing else { return }
        isDismissing = true
        isShown = false
        dismissOnResign = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // A reveal during the fade clears the flag and claims the window.
                guard self.isDismissing else { return }
                self.orderOut(nil)
            }
        })
    }

    /// The launcher fades out when it loses key focus — clicking another app or
    /// window, or switching away. This replaces the activation-based auto-hide
    /// that was racing with the global hotkey.
    override func dismissOnFocusLoss() { dismiss(animated: true) }

    /// Clicks land on the transparent shadow halo, which no longer sits over
    /// another app, so they have to close the launcher themselves.
    public override func mouseDown(with event: NSEvent) {
        let inset = Self.shadowPadding
        if let content = contentView, !content.bounds.insetBy(dx: inset, dy: inset)
            .contains(event.locationInWindow) {
            dismiss(animated: true)
            return
        }
        super.mouseDown(with: event)
    }

    public func toggle() {
        if isVisible && !isDismissing {
            dismiss(animated: true)
        } else {
            pendingHeight = nil
            resizeToHeight(lastHeight)
            reveal()
        }
    }

    /// The window frame carries the shadow halo, so SwiftUI is told the smaller
    /// content size.
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        applyingFrame = true
        super.setFrame(frameRect, display: flag)
        applyingFrame = false
        let pad = Self.shadowPadding
        windowFrame.size = NSSize(width: frame.width - 2 * pad, height: frame.height - 2 * pad)
        pinHost()
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

    /// `height` is the content height; the window also carries the shadow halo.
    private func applySizeLimits(in visible: CGRect, height: CGFloat) {
        let pad = Self.shadowPadding
        let width = LauncherPlacement.width(in: visible) + 2 * pad
        let size = NSSize(width: width, height: height + 2 * pad)
        minSize = size
        maxSize = size
    }

}

private final class HostPinView: NSView {
    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }
}

/// Charcoal wash over the vibrancy.
///
/// Behind-window blur takes its color from whatever sits behind the panel, so
/// the launcher turns pale gray over a light window. This tint is opaque enough
/// to hold the background near the same dark tone everywhere while the blur
/// still shows through. Light mode keeps plain vibrancy.
private let launcherTint = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(white: 0.17, alpha: 0.88)
        : .clear
}

/// A layer-backed view whose look is one closure, re-run whenever the
/// appearance or the backing scale changes.
private final class PaintedView: NSView {
    private let paint: (PaintedView) -> Void
    private let clickable: Bool

    init(frame: NSRect = .zero, clickable: Bool = true, paint: @escaping (PaintedView) -> Void) {
        self.paint = paint
        self.clickable = clickable
        super.init(frame: frame)
        wantsLayer = true
        repaint()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { clickable ? super.hitTest(point) : nil }

    override func viewDidChangeEffectiveAppearance() { repaint() }

    override func viewDidChangeBackingProperties() { repaint() }

    private func repaint() {
        effectiveAppearance.performAsCurrentDrawingAppearance { paint(self) }
    }
}

/// Transparent halo around the launcher chrome, holding the panel's shadow.
///
/// `NSWindow.hasShadow` exposes no radius, offset, or opacity, and a layer
/// shadow on the chrome itself is clipped away by the corner-radius mask. So
/// the window is oversized by `padding` and an unclipped sibling layer under
/// the chrome casts the shadow into that margin.
private final class ShadowContainerView: NSView {
    let chrome: NSView
    private let shadowView: ShadowView
    /// Hairline on the panel edge; decoration only, so the chrome underneath
    /// keeps the clicks. Its width is a device pixel, so the line stays a
    /// hairline on Retina.
    ///
    /// It shares the chrome's frame and radius rather than sitting a point
    /// inside a radius one smaller. That arithmetic is only concentric for a
    /// circular corner: these corners are `.continuous`, and the offset curve of
    /// a squircle is not another squircle, so the two paths part company
    /// diagonally into the corner. On Retina the gap hides under a half-point
    /// line, but at 1x the line doubles in width and the corner shows a bright
    /// notch where the hairline pulls away from the edge. `borderWidth` draws
    /// inward from the bounds, so an identical frame puts it in the same place
    /// the inset was aiming for, on whatever curve the chrome actually has.
    private let hairline: PaintedView = {
        let view = PaintedView(clickable: false) { view in
            view.layer?.borderWidth = 1 / (view.window?.backingScaleFactor ?? 2)
            view.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.25).cgColor
        }
        view.layer?.cornerRadius = LauncherPanel.cornerRadius
        view.layer?.cornerCurve = .continuous
        return view
    }()

    var drawsShadow = true {
        didSet { paint() }
    }

    /// Both children are inset by `padding` and autoresize with fixed margins,
    /// so the halo survives without a layout pass.
    init(chrome: NSView, padding: CGFloat, cornerRadius: CGFloat) {
        self.chrome = chrome
        shadowView = ShadowView(cornerRadius: cornerRadius)
        let size = NSSize(
            width: chrome.frame.width + 2 * padding,
            height: chrome.frame.height + 2 * padding
        )
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.masksToBounds = false
        let inner = bounds.insetBy(dx: padding, dy: padding)
        shadowView.frame = inner
        chrome.frame = inner
        hairline.frame = inner
        for view in [shadowView, chrome, hairline] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        paint()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        paint()
    }

    /// Heavier over dark desktops, where the panel would otherwise float
    /// edgeless.
    private func paint() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        shadowView.opacity = drawsShadow ? (dark ? 0.7 : 0.45) : 0
    }
}

/// The shadow caster: an opaque rounded rect the chrome sits exactly on top of.
///
/// The shadow goes through `NSView.shadow` rather than the layer's own
/// `shadowOpacity`. AppKit syncs that property onto the backing layer of every
/// layer-backed view, so hand-set layer shadows are wiped on the next display.
private final class ShadowView: NSView {
    private static let blurRadius = LauncherPlacement.shadowBlur
    private static let offset = NSSize(width: 0, height: -LauncherPlacement.shadowDrop)

    var opacity: CGFloat = 0 {
        didSet { apply() }
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        // The fill is what casts; the chrome covers it pixel for pixel.
        layer?.backgroundColor = NSColor.black.cgColor
        apply()
    }

    required init?(coder: NSCoder) { nil }

    /// Layer coordinates are unflipped, so a negative height drops the shadow
    /// below the panel.
    private func apply() {
        guard opacity > 0 else {
            shadow = nil
            return
        }
        let drop = NSShadow()
        drop.shadowColor = NSColor.black.withAlphaComponent(opacity)
        drop.shadowBlurRadius = Self.blurRadius
        drop.shadowOffset = Self.offset
        shadow = drop
    }
}

