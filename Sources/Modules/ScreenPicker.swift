// ScreenPicker.swift — drag a rectangle over the screen
import MacotronEngine
import AppKit

@MainActor
final class ScreenRegionPicker {
    static let shared = ScreenRegionPicker()

    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var overlays: [PickerOverlay] = []
    private var keyMonitor: Any?

    func pick() async -> CGRect? {
        if continuation != nil { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            start()
        }
    }

    private func start() {
        AppActivation.activate("screen picker")
        NSCursor.crosshair.push()
        overlays = NSScreen.screens.map { screen in
            let overlay = PickerOverlay(screen: screen) { [weak self] rect in
                self?.finish(rect)
            }
            overlay.show()
            return overlay
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(nil)
                return nil
            }
            return event
        }
    }

    private func finish(_ rect: CGRect?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSCursor.pop()
        overlays.forEach { $0.close() }
        overlays.removeAll()
        continuation?.resume(returning: rect)
        continuation = nil
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PickerOverlay {
    private let panel: NSPanel
    private let view: PickerView

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = onComplete
        self.view = view

        let panel = PickerPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        self.panel = panel
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }
}

@MainActor
private final class PickerView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selection, rect.width >= 8, rect.height >= 8,
              let window else {
            onComplete?(nil)
            return
        }
        onComplete?(window.convertToScreen(rect))
    }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        guard let selection, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fill(selection)
        ctx.restoreGState()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 2
        path.stroke()
    }
}
