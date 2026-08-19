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
    private static let panelWidth: CGFloat = 720
    private static let minHeight: CGFloat = 52  // Search bar only
    private static let maxHeight: CGFloat = 520
    private static let cornerRadius: CGFloat = 12

    private let hostingView: NSView
    private var pendingReveal = false
    /// Cached content height from the last layout pass — used to open at the right size.
    private var lastContentHeight: CGFloat = 0
    public var onHide: (() -> Void)?
    /// App that was frontmost before we activated, so Escape can give typing back.
    private var appToRestore: NSRunningApplication?
    private var shouldRestoreApp = false
    private var isOrderingOut = false

    public init(contentView: NSView) {
        hostingView = contentView
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.maxHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        minSize = NSSize(width: Self.panelWidth, height: Self.minHeight)
        maxSize = NSSize(width: Self.panelWidth, height: Self.maxHeight)
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        center()
        applyBackground(.translucent)
        self.delegate = self
    }

    public func applyBackground(_ style: LauncherBackground) {
        hostingView.removeFromSuperview()
        if #available(macOS 26.0, *) {
            Self.glass(in: contentView)?.contentView = nil
        }
        let height = lastContentHeight > 0 ? lastContentHeight : Self.minHeight
        let chrome = Self.makeChrome(style, size: NSSize(width: Self.panelWidth, height: height))
        hostingView.frame = chrome.bounds
        hostingView.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = Self.glass(in: chrome) {
            glass.contentView = hostingView
        } else {
            chrome.addSubview(hostingView)
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
        let clamped = min(max(height, Self.minHeight), Self.maxHeight)
        lastContentHeight = clamped

        if pendingReveal {
            // First height report after toggle — snap to correct size and reveal.
            let topY = frame.maxY
            var newFrame = frame
            newFrame.size.height = clamped
            newFrame.origin.y = topY - clamped
            setFrame(newFrame, display: true)
            reveal()
            return
        }

        guard abs(frame.height - clamped) > 1 else { return }

        let topY = frame.maxY
        var newFrame = frame
        newFrame.size.height = clamped
        newFrame.origin.y = topY - clamped
        setFrame(newFrame, display: true)
    }

    private func reveal() {
        pendingReveal = false
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
        pendingReveal = false
        isShown = false
        if wasVisible {
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

    public func toggle() {
        if isVisible {
            shouldRestoreApp = true
            orderOut(nil)
        } else {
            captureFrontApp()
            // Use cached height on subsequent opens to avoid the tall-then-shrink flash.
            // On first open, use maxHeight so SwiftUI has full space for layout.
            let initialHeight = lastContentHeight > 0 ? lastContentHeight : Self.maxHeight

            var f = frame
            f.size.height = initialHeight
            setFrame(f, display: false)

            // Place the launcher centered horizontally in the upper portion of the screen.
            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                let x = sf.midX - Self.panelWidth / 2
                let topY = sf.minY + sf.height * 0.78
                let y = topY - initialHeight
                setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                center()
            }

            if lastContentHeight > 0 {
                // We know the right height — show immediately at the cached size.
                // SwiftUI will animate-adjust if content changed since last close.
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
                if let textField = contentView?.firstEditableTextField() {
                    makeFirstResponder(textField)
                }
                isShown = true
            } else {
                // First open — show invisible, wait for SwiftUI to report height.
                alphaValue = 0
                pendingReveal = true
                makeKeyAndOrderFront(nil)

                // Safety fallback if SwiftUI doesn't report height quickly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self, self.pendingReveal else { return }
                    self.reveal()
                }
            }
        }
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
