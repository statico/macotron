import AppKit
import MacotronEngine
import SwiftUI

public struct ShowHotkeysRow: Equatable, Identifiable {
    public let id: String
    public let combo: String
    public let label: String

    public init(id: String, combo: String, label: String) {
        self.id = id
        self.combo = combo
        self.label = label
    }
}

struct HotkeysOverlayView: View {
    let rows: [ShowHotkeysRow]

    static func height(for rowCount: Int) -> CGFloat {
        min(480, max(120, CGFloat(rowCount) * 34 + 72))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            if rows.isEmpty {
                Text("No shortcuts are bound yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Text(row.label)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                HStack(spacing: 2) {
                                    ForEach(KeyCombo.glyphs(row.combo), id: \.self) { part in
                                        Text(part)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.primary.opacity(0.06))
                                            )
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

@MainActor
public final class HotkeysOverlayPanel: NonactivatingPanel {
    private static let width: CGFloat = 420

    private let hostingView: NSHostingView<HotkeysOverlayView>

    public init() {
        hostingView = NSHostingView(rootView: HotkeysOverlayView(rows: []))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureFloatingPanel()
        hasShadow = true
        applyChrome()
    }

    public func toggle(rows: [ShowHotkeysRow]) {
        if isVisible || isShown {
            dismiss()
        } else {
            present(rows: rows)
        }
    }

    private func present(rows: [ShowHotkeysRow]) {
        hostingView.rootView = HotkeysOverlayView(rows: rows)
        let visible = LauncherPlacement.currentVisible()
        let height = HotkeysOverlayView.height(for: rows.count)
        setFrame(
            CGRect(
                x: visible.midX - Self.width / 2,
                y: visible.midY - height / 2,
                width: Self.width,
                height: height
            ),
            display: false
        )
        applyChrome()
        alphaValue = 1
        dismissOnResign = false
        orderFrontRegardless()
        makeKey()
        isShown = true
        armDismissOnResign()
    }

    public func dismiss() {
        guard isVisible || isShown else { return }
        orderOut(nil)
    }

    /// The shadow is cached from the panel's shape, so a resize leaves it drawn
    /// around the old bounds until it is invalidated.
    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        invalidateShadow()
    }

    public override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    private func applyChrome() {
        hostingView.removeFromSuperview()
        let visual = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
        visual.material = .hudWindow
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 12
        visual.layer?.masksToBounds = true
        visual.autoresizingMask = [.width, .height]
        hostingView.frame = visual.bounds
        hostingView.autoresizingMask = [.width, .height]
        visual.addSubview(hostingView)
        contentView = visual
        invalidateShadow()
    }
}
