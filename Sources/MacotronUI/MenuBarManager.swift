// MenuBarManager.swift — NSStatusItem + dynamic NSMenu for menubar dropdown
import AppKit
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "menubar")

/// Small circle drawn over the status item glyph.
private final class BadgeDotView: NSView {
    var fill = NSColor.systemRed

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

@MainActor
public final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    public struct MenuItemConfig {
        public let title: String
        public let icon: String?
        public let section: String?
        public let callback: (() -> Void)?
        public let menu: [MenuBarEntry]

        public init(title: String, icon: String? = nil, section: String? = nil, callback: (() -> Void)? = nil, menu: [MenuBarEntry] = []) {
            self.title = title
            self.icon = icon
            self.section = section
            self.callback = callback
            self.menu = menu
        }
    }

    /// Extra NSStatusItems registered by plugins, next to the Macotron icon.
    private var extraStatusItems: [String: PluginStatusItem] = [:]
    private var statusRegistered: Set<String>?
    private var pluginMenuBoxes: [PluginMenu.Action] = []

    /// Items registered by JS plugins, keyed by ID
    private var dynamicItems: [(id: String, config: MenuItemConfig)] = []

    /// Current launcher shortcut combo string (e.g. "opt+space"), used for menu display
    private var launcherShortcut: String = "opt+space"

    /// SF Symbol set by a JS plugin, or nil to use the Macotron glyph.
    /// Redrawn when the permission warning changes.
    private var symbolName: String?
    private var iconColor: NSColor?
    private var iconColorThisReload = false

    /// Required permissions the user has not granted yet.
    private var missingPermissions: [Permission] = []
    private var hotReload = false
    private var pendingReviewCount = 0

    /// Dot overlay on the status button.
    private var badgeView: NSView?

    public var onReload: (() -> Void)?
    public var onOpenConfig: (() -> Void)?
    public var onToggleLauncher: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenPermissions: (() -> Void)?
    public var onToggleHotReload: ((Bool) -> Void)?
    public var onReviewPending: (() -> Void)?

    /// Called before the menu opens, so permission state is never stale.
    public var onMenuWillOpen: (() -> Void)?

    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusImage()
        rebuildMenu()
    }

    // MARK: - Permission warning

    /// Show or clear the red warning dot and the red menu row.
    public func setMissingPermissions(_ permissions: [Permission]) {
        guard permissions != missingPermissions else { return }
        missingPermissions = permissions
        refreshStatusImage()
        rebuildMenu()
    }

    public func setIntegrityState(hotReload: Bool, pendingCount: Int) {
        guard hotReload != self.hotReload || pendingCount != pendingReviewCount else { return }
        self.hotReload = hotReload
        pendingReviewCount = pendingCount
        refreshStatusImage()
        rebuildMenu()
    }

    // MARK: - Public API (called from JS)

    public func addItem(id: String, config: MenuItemConfig) {
        if let idx = dynamicItems.firstIndex(where: { $0.id == id }) {
            let old = dynamicItems[idx].config
            dynamicItems[idx] = (id: id, config: config)
            if old.section == config.section, old.menu.isEmpty, config.menu.isEmpty,
               let item = menuItem(id: id) {
                PluginMenu.apply(title: config.title, icon: config.icon, to: item)
                return
            }
            rebuildMenu()
            return
        }
        dynamicItems.append((id: id, config: config))
        rebuildMenu()
    }

    public func updateItem(id: String, title: String? = nil, icon: String? = nil) {
        guard let idx = dynamicItems.firstIndex(where: { $0.id == id }) else { return }
        let old = dynamicItems[idx].config
        let updated = MenuItemConfig(
            title: title ?? old.title,
            icon: icon ?? old.icon,
            section: old.section,
            callback: old.callback,
            menu: old.menu
        )
        dynamicItems[idx] = (id: id, config: updated)
        if let item = menuItem(id: id) {
            PluginMenu.apply(title: updated.title, icon: updated.icon, to: item)
            return
        }
        rebuildMenu()
    }

    public func removeItem(id: String) {
        dynamicItems.removeAll { $0.id == id }
        rebuildMenu()
    }

    public func setIcon(_ sfSymbolName: String) {
        symbolName = sfSymbolName
        refreshStatusImage()
    }

    public func setIconColor(_ raw: String?) {
        iconColorThisReload = true
        iconColor = PluginStatusItem.parseColor(raw)
        logger.info("setIconColor \(raw ?? "nil", privacy: .public) parsed=\(self.iconColor != nil, privacy: .public)")
        refreshStatusImage()
    }

    /// Extra status items bake color into the image because `contentTintColor`
    /// on `NSStatusBarButton` does not tint a custom glyph on Tahoe. Same here:
    /// a colored icon is an original image; the default glyph stays a template.
    private func refreshStatusImage() {
        guard let button = statusItem.button else { return }
        if let symbolName {
            let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Macotron")
            if let iconColor, let configured = base?.withSymbolConfiguration(
                .init(paletteColors: [iconColor])
            ) {
                // Rasterize, as PluginStatusItem does: the status bar button
                // re-applies its own symbol configuration to a symbol-backed
                // image, which drops the palette color. A handler-backed image
                // keeps the color we baked in.
                let flat = NSImage(size: configured.size, flipped: false) { rect in
                    configured.draw(in: rect)
                    return true
                }
                flat.isTemplate = false
                button.image = flat
            } else {
                base?.isTemplate = true
                button.image = base
            }
        } else {
            button.image = MenuBarIcon.makeImage(tint: iconColor)
        }
        button.contentTintColor = nil
        // A new image of the same size does not always mark the button dirty,
        // which leaves an animated icon frozen on its first frame.
        button.needsDisplay = true

        // Permission dot is a sibling; badging the image would force a
        // non-template icon and a fixed color.
        badgeView?.removeFromSuperview()
        badgeView = nil

        let showRed = !missingPermissions.isEmpty
        let showOrange = hotReload || pendingReviewCount > 0
        guard showRed || showOrange else {
            button.toolTip = nil
            return
        }

        // Hot reload is a mode, not a warning: give it a reload glyph so it
        // does not read as the same "something is wrong" dot.
        let hotReloadOnly = !showRed && pendingReviewCount == 0
        let badge: NSView
        let side: CGFloat
        if hotReloadOnly, let glyph = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Hot Reload is on"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
                .applying(.init(paletteColors: [.systemOrange]))
        ) {
            let view = NSImageView(image: glyph)
            view.imageScaling = .scaleProportionallyUpOrDown
            badge = view
            side = 9
        } else {
            let dot = BadgeDotView()
            dot.fill = showRed ? .systemRed : .systemOrange
            badge = dot
            side = 6
        }
        badge.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: side),
            badge.heightAnchor.constraint(equalToConstant: side),
            badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            badge.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
        ])
        badgeView = badge
        if showRed {
            button.toolTip = "Macotron needs permissions"
        } else if pendingReviewCount > 0 {
            button.toolTip = "Plugin files changed and need review"
        } else {
            button.toolTip = "Hot Reload is on"
        }
    }

    public func setTitle(_ text: String) {
        statusItem.button?.title = text
    }

    public func setStatus(
        id: String,
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
        menu: [MenuBarEntry] = [],
        required: Bool = true
    ) {
        let extra = extraStatusItems[id] ?? PluginStatusItem(id: id)
        extraStatusItems[id] = extra
        extra.required = required
        extra.onVisibilityChange = { [weak self] id, visible in
            self?.statusVisibilityChanged(id: id, visible: visible)
        }
        statusRegistered?.insert(id)
        // An item dragged out stays out across launches, so it can come up
        // hidden; the observer above only fires on a change and would never
        // mention it.
        statusVisibilityChanged(id: id, visible: extra.isVisible)
        extra.apply(
            title: title,
            subtitle: subtitle,
            color: color,
            subtitleColor: subtitleColor,
            bold: bold,
            italic: italic,
            secondary: secondary,
            minWidth: minWidth,
            sfSymbol: sfSymbol,
            imagePath: imagePath,
            onClick: onClick,
            menu: menu
        )
    }

    public func removeStatus(id: String) {
        extraStatusItems.removeValue(forKey: id)?.remove()
        if hiddenStatusIDs.remove(id) != nil { onHiddenStatusChange?(hiddenStatusIDs) }
    }

    /// Ids of items the user dragged out of the menu bar that their plugin
    /// expects to be there.
    public private(set) var hiddenStatusIDs: Set<String> = []
    public var onHiddenStatusChange: ((Set<String>) -> Void)?

    public func restoreStatus(id: String) {
        extraStatusItems[id]?.restore()
    }

    /// How many items plugins asked for, and how many of those are not showing.
    public func statusItemCounts() -> (total: Int, hidden: Int) {
        let required = extraStatusItems.values.filter(\.required)
        return (required.count, required.filter { !$0.isVisible }.count)
    }

    public func restoreAllStatus() {
        extraStatusItems.values.filter(\.required).forEach { $0.restore() }
    }

    private func statusVisibilityChanged(id: String, visible: Bool) {
        guard let item = extraStatusItems[id], item.required else { return }
        let changed = visible ? hiddenStatusIDs.remove(id) != nil : hiddenStatusIDs.insert(id).inserted
        guard changed else { return }
        logger.info("status \(id, privacy: .public) visible=\(visible, privacy: .public)")
        onHiddenStatusChange?(hiddenStatusIDs)
    }

    public func removeAllStatus() {
        extraStatusItems.values.forEach { $0.remove() }
        extraStatusItems.removeAll()
        guard !hiddenStatusIDs.isEmpty else { return }
        hiddenStatusIDs.removeAll()
        onHiddenStatusChange?(hiddenStatusIDs)
    }

    public func beginStatusReload() {
        statusRegistered = []
        iconColorThisReload = false
    }

    public func finishStatusReload() {
        guard let registered = statusRegistered else { return }
        statusRegistered = nil
        for id in extraStatusItems.keys where !registered.contains(id) {
            removeStatus(id: id)
        }
        if !iconColorThisReload, iconColor != nil {
            iconColor = nil
            refreshStatusImage()
        }
    }

    public func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    public func updateLauncherShortcut(_ combo: String) {
        launcherShortcut = combo
        rebuildMenu()
    }

    // MARK: - Menu Building

    private func menuItem(id: String) -> NSMenuItem? {
        menu.items.first { $0.representedObject as? String == id }
    }

    private func parseHotkey(_ combo: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        KeyCombo.parse(combo)?.menuEquivalent ?? ("", [])
    }

    private func rebuildMenu() {
        StepTimer.measure("rebuildMenu") { rebuildMenuBody() }
    }

    private func rebuildMenuBody() {
        menu.removeAllItems()

        pluginMenuBoxes.removeAll()

        addPermissionWarningIfNeeded()
        addIntegrityWarningIfNeeded()

        // Group dynamic items by section
        let sections = Dictionary(grouping: dynamicItems, by: { $0.config.section ?? "" })
        let sectionOrder = sections.keys.sorted()

        for section in sectionOrder {
            if !section.isEmpty {
                menu.addItem(.separator())
                let header = NSMenuItem(title: section, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            }
            for item in sections[section]! {
                let menuItem = PluginMenu.item(title: item.config.title, icon: item.config.icon)
                if !item.config.menu.isEmpty {
                    menuItem.submenu = PluginMenu.make(item.config.menu, retaining: &pluginMenuBoxes)
                } else {
                    menuItem.action = #selector(menuItemClicked(_:))
                    menuItem.target = self
                    menuItem.representedObject = item.id
                }
                menu.addItem(menuItem)
            }
        }

        // Standard items at bottom
        menu.addItem(.separator())

        let (launcherKey, launcherMods) = parseHotkey(launcherShortcut)
        let openLauncher = NSMenuItem(title: "Open Launcher", action: #selector(openLauncherAction), keyEquivalent: launcherKey)
        openLauncher.keyEquivalentModifierMask = launcherMods
        openLauncher.target = self
        openLauncher.image = Self.menuSymbol("magnifyingglass")
        menu.addItem(openLauncher)

        let reload = NSMenuItem(title: "Reload Plugins", action: #selector(reloadAction), keyEquivalent: "r")
        reload.target = self
        reload.image = Self.menuSymbol("arrow.clockwise")
        menu.addItem(reload)

        let hotReloadItem = NSMenuItem(
            title: hotReload ? "Disable Hot Reloading" : "Enable Hot Reloading",
            action: #selector(toggleHotReloadAction),
            keyEquivalent: ""
        )
        hotReloadItem.target = self
        hotReloadItem.image = Self.menuSymbol(hotReload ? "bolt.slash" : "bolt")
        menu.addItem(hotReloadItem)

        if pendingReviewCount > 0 {
            let review = NSMenuItem(
                title: "Review & Reload (\(pendingReviewCount))",
                action: #selector(reviewPendingAction),
                keyEquivalent: ""
            )
            review.target = self
            review.image = Self.menuSymbol("exclamationmark.triangle")
            menu.addItem(review)
        }

        let openConfig = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigAction), keyEquivalent: ",")
        openConfig.target = self
        openConfig.image = Self.menuSymbol("folder")
        menu.addItem(openConfig)

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: "")
        settings.target = self
        settings.image = Self.menuSymbol("gearshape")
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Macotron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Self.menuSymbol("xmark.circle")
        menu.addItem(quit)
    }

    private static func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// Red row at the top of the menu naming every missing permission.
    private func addPermissionWarningIfNeeded() {
        guard !missingPermissions.isEmpty else { return }

        let names = missingPermissions.map(\.title).joined(separator: ", ")
        let item = NSMenuItem(
            title: "Permissions needed",
            action: #selector(openPermissionsAction),
            keyEquivalent: ""
        )
        item.target = self
        item.attributedTitle = NSAttributedString(
            string: "Permissions needed: \(names)",
            attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 0),
            ]
        )
        item.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        menu.addItem(item)

        let hint = NSMenuItem(title: "Open Settings to grant…", action: #selector(openPermissionsAction), keyEquivalent: "")
        hint.target = self
        hint.attributedTitle = NSAttributedString(
            string: "Open Settings to grant…",
            attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            ]
        )
        menu.addItem(hint)
        menu.addItem(.separator())
    }

    private func addIntegrityWarningIfNeeded() {
        guard missingPermissions.isEmpty else { return }
        if pendingReviewCount > 0 {
            let item = NSMenuItem(
                title: "Plugin files changed",
                action: #selector(reviewPendingAction),
                keyEquivalent: ""
            )
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: "\(pendingReviewCount) plugin file(s) changed — Review & Reload",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.menuFont(ofSize: 0),
                ]
            )
            menu.addItem(item)
            menu.addItem(.separator())
        } else if hotReload {
            let item = NSMenuItem(title: "Hot Reload is on", action: #selector(toggleHotReloadAction), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: "Hot Reload is on — plugins load without a scan",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.menuFont(ofSize: 0),
                ]
            )
            menu.addItem(item)
            menu.addItem(.separator())
        }
    }

    @objc private func openPermissionsAction() {
        onOpenPermissions?()
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = dynamicItems.first(where: { $0.id == id }) else { return }
        item.config.callback?()
    }

    @objc private func openLauncherAction() {
        onToggleLauncher?()
    }

    @objc private func reloadAction() {
        onReload?()
    }

    @objc private func openConfigAction() {
        onOpenConfig?()
    }

    @objc private func openSettingsAction() {
        onOpenSettings?()
    }

    @objc private func toggleHotReloadAction() {
        onToggleHotReload?(!hotReload)
    }

    @objc private func reviewPendingAction() {
        onReviewPending?()
    }
}

extension MenuBarManager: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        StepTimer.measure("menuNeedsUpdate") { onMenuWillOpen?() }
    }
}
