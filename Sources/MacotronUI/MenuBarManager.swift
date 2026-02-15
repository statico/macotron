// MenuBarManager.swift — NSStatusItem + dynamic NSMenu for menubar dropdown
import AppKit
import MacotronEngine

@MainActor
public final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    public struct MenuItemConfig {
        public let title: String
        public let icon: String?
        public let section: String?
        public let callback: (() -> Void)?

        public init(title: String, icon: String? = nil, section: String? = nil, callback: (() -> Void)? = nil) {
            self.title = title
            self.icon = icon
            self.section = section
            self.callback = callback
        }
    }

    /// Items registered by JS snippets, keyed by ID
    private var dynamicItems: [(id: String, config: MenuItemConfig)] = []

    public var onReload: (() -> Void)?
    public var onOpenConfig: (() -> Void)?
    public var onToggleLauncher: (() -> Void)?
    public var onOpenSettings: (() -> Void)?

    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Macotron"
        )
        menu = NSMenu()
        statusItem.menu = menu
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
            callback: old.callback
        )
        dynamicItems[idx] = (id: id, config: updated)
        rebuildMenu()
    }

    public func removeItem(id: String) {
        dynamicItems.removeAll { $0.id == id }
        rebuildMenu()
    }

    public func clearDynamicItems() {
        dynamicItems.removeAll()
        rebuildMenu()
    }

    public func setIcon(_ sfSymbolName: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: sfSymbolName,
            accessibilityDescription: "Macotron"
        )
    }

    public func setTitle(_ text: String) {
        statusItem.button?.title = text
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        menu.removeAllItems()

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
                let menuItem = NSMenuItem(
                    title: item.config.title,
                    action: #selector(menuItemClicked(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item.id

                if let icon = item.config.icon {
                    if icon.count <= 2 {
                        menuItem.title = "\(icon) \(item.config.title)"
                    } else {
                        menuItem.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
                    }
                }
                menu.addItem(menuItem)
            }
        }

        // Standard items at bottom
        menu.addItem(.separator())

        let openLauncher = NSMenuItem(title: "Open Launcher", action: #selector(openLauncherAction), keyEquivalent: " ")
        openLauncher.target = self
        menu.addItem(openLauncher)

        let reload = NSMenuItem(title: "Reload Snippets", action: #selector(reloadAction), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let openConfig = NSMenuItem(title: "Open Config Folder", action: #selector(openConfigAction), keyEquivalent: ",")
        openConfig.target = self
        menu.addItem(openConfig)

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Macotron", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
