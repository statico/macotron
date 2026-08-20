// MenuBarManager.swift — NSStatusItem + dynamic NSMenu for menubar dropdown
import AppKit
import MacotronEngine

/// Small red circle drawn over the status item glyph.
private final class BadgeDotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
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

    /// Items registered by JS modules, keyed by ID
    private var dynamicItems: [(id: String, config: MenuItemConfig)] = []

    /// Current launcher shortcut combo string (e.g. "cmd+space"), used for menu display
    private var launcherShortcut: String = "cmd+space"

    /// SF Symbol set by a JS module, or nil to use the Macotron glyph.
    /// Redrawn when the permission warning changes.
    private var symbolName: String?
    private var iconColor: NSColor?
    private var iconColorThisReload = false

    /// Required permissions the user has not granted yet.
    private var missingPermissions: [Permission] = []

    /// Red dot overlay shown on the status button while permissions are missing.
    private var badgeView: NSView?

    public var onReload: (() -> Void)?
    public var onOpenConfig: (() -> Void)?
    public var onToggleLauncher: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onOpenPermissions: (() -> Void)?

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

    // MARK: - Public API (called from JS)

    public func addItem(id: String, config: MenuItemConfig) {
        dynamicItems.removeAll { $0.id == id }
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
        refreshStatusImage()
    }

    /// Extra status items bake color into the image because `contentTintColor`
    /// on `NSStatusBarButton` does not tint a custom glyph on Tahoe. Same here:
    /// a colored icon is an original image; the default glyph stays a template.
    private func refreshStatusImage() {
        guard let button = statusItem.button else { return }
        if let symbolName {
            let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Macotron")
            if let iconColor {
                button.image = base?.withSymbolConfiguration(.init(paletteColors: [iconColor]))
                button.image?.isTemplate = false
            } else {
                base?.isTemplate = true
                button.image = base
            }
        } else {
            button.image = MenuBarIcon.makeImage(tint: iconColor)
        }
        button.contentTintColor = nil

        // Permission dot is a sibling; badging the image would force a
        // non-template icon and a fixed color.
        badgeView?.removeFromSuperview()
        badgeView = nil

        guard !missingPermissions.isEmpty else {
            button.toolTip = nil
            return
        }

        let dot = BadgeDotView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 4),
        ])
        badgeView = dot
        button.toolTip = "Macotron needs permissions"
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
        menu: [MenuBarEntry] = []
    ) {
        let extra = extraStatusItems[id] ?? PluginStatusItem(id: id)
        extraStatusItems[id] = extra
        statusRegistered?.insert(id)
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
    }

    public func removeAllStatus() {
        extraStatusItems.values.forEach { $0.remove() }
        extraStatusItems.removeAll()
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

    /// Parse a hotkey combo string (e.g. "cmd+shift+k") into an NSMenuItem key equivalent and modifier mask.
    private func parseHotkey(_ combo: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        let parts = combo.lowercased().split(separator: "+")
        var modifiers: NSEvent.ModifierFlags = []
        var key = ""

        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "alt", "option": modifiers.insert(.option)
            case "space": key = " "
            case "return", "enter": key = "\r"
            case "tab": key = "\t"
            default: key = String(part)
            }
        }

        return (key, modifiers)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        pluginMenuBoxes.removeAll()

        addPermissionWarningIfNeeded()

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

        let reload = NSMenuItem(title: "Reload Modules", action: #selector(reloadAction), keyEquivalent: "r")
        reload.target = self
        reload.image = Self.menuSymbol("arrow.clockwise")
        menu.addItem(reload)

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
}

extension MenuBarManager: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        onMenuWillOpen?()
    }
}
