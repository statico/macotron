import Foundation

public struct CatalogPlugin: Equatable, Identifiable, Sendable {
    public var filename: String
    public var highlighted: Bool
    public var category: String
    public var title: String
    public var description: String
    public var permissions: [Permission]
    public var source: String
    public var bundleHash: String
    public var fileURL: URL

    public var id: String { filename }

    public init(
        filename: String,
        highlighted: Bool,
        category: String,
        title: String,
        description: String,
        permissions: [Permission],
        source: String,
        bundleHash: String,
        fileURL: URL
    ) {
        self.filename = filename
        self.highlighted = highlighted
        self.category = category
        self.title = title
        self.description = description
        self.permissions = permissions
        self.source = source
        self.bundleHash = bundleHash
        self.fileURL = fileURL
    }
}

public enum PluginCatalog {
    public static func load(bundle: Bundle = .main) -> [CatalogPlugin] {
        let jsonURL = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Catalog")
            ?? bundle.url(forResource: "catalog", withExtension: "json")
        guard let jsonURL else { return [] }
        return load(jsonURL: jsonURL)
    }

    public static func load(jsonURL: URL) -> [CatalogPlugin] {
        guard let data = try? Data(contentsOf: jsonURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["plugins"] as? [[String: Any]] else {
            return []
        }
        let catalogDir = jsonURL.deletingLastPathComponent()
        return rows.compactMap { row in
            guard let filename = row["filename"] as? String else { return nil }
            let fileURL = catalogDir.appending(path: filename)
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
            let header = PluginHeader.parse(source)
            let perms = header.permissions.compactMap(Permission.init(rawValue:))
            return CatalogPlugin(
                filename: filename,
                highlighted: row["highlighted"] as? Bool ?? false,
                category: row["category"] as? String ?? "Other",
                title: header.title ?? String(filename.dropLast(3)),
                description: header.description ?? "",
                permissions: perms,
                source: source,
                bundleHash: PluginHash.sha256(source: source),
                fileURL: fileURL
            )
        }
        .sorted { lhs, rhs in
            if lhs.highlighted != rhs.highlighted { return lhs.highlighted && !rhs.highlighted }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public static func overwriteKind(existingHash: String?, bundledHash: String) -> CatalogOverwrite? {
        guard let existingHash else { return nil }
        if existingHash == bundledHash { return .unmodifiedBuiltIn }
        return .modified
    }

    /// Every one-to-one rename Macotron shipped when built-in plugins dropped the
    /// `demo-` prefix. The list is closed: new catalog entries never need a rename,
    /// and `demo-night-vision.js`, `demo-gamma-black.js`, and `demo-display-modes.js`
    /// stay put because `screen-effects.js` replaced all three.
    public static let legacyRenames: [String: String] = [
        "demo-ai-chat.js": "ai-chat.js",
        "demo-appearance.js": "appearance.js",
        "demo-audio.js": "audio.js",
        "demo-batch-rename.js": "batch-rename.js",
        "demo-battery.js": "battery.js",
        "demo-brightness.js": "brightness.js",
        "demo-browser-picker.js": "browser-picker.js",
        "demo-browser-profiles.js": "browser-profiles.js",
        "demo-calculator.js": "calculator.js",
        "demo-calendar.js": "calendar.js",
        "demo-clipboard-history.js": "clipboard-history.js",
        "demo-clipboard-image.js": "clipboard-image.js",
        "demo-color-picker.js": "color-picker.js",
        "demo-cpu-graph.js": "cpu-graph.js",
        "demo-datetime.js": "datetime.js",
        "demo-devutils.js": "devutils.js",
        "demo-disk-usage.js": "disk-usage.js",
        "demo-fan.js": "fan.js",
        "demo-file-search.js": "file-search.js",
        "demo-focus-idle.js": "focus-idle.js",
        "demo-gestures.js": "gestures.js",
        "demo-heic-to-jpeg.js": "heic-to-jpeg.js",
        "demo-hid.js": "hid.js",
        "demo-hyper.js": "hyper.js",
        "demo-icon-rainbow.js": "icon-rainbow.js",
        "demo-idle.js": "idle.js",
        "demo-layouts.js": "layouts.js",
        "demo-lock-screen.js": "lock-screen.js",
        "demo-lorem.js": "lorem.js",
        "demo-meeting-overlay.js": "meeting-overlay.js",
        "demo-meetings.js": "meetings.js",
        "demo-notes.js": "notes.js",
        "demo-now-playing.js": "now-playing.js",
        "demo-ocr.js": "ocr.js",
        "demo-plain-paste.js": "plain-paste.js",
        "demo-pomodoro.js": "pomodoro.js",
        "demo-power.js": "power.js",
        "demo-present-mode.js": "present-mode.js",
        "demo-qr.js": "qr.js",
        "demo-record.js": "record.js",
        "demo-regex.js": "regex.js",
        "demo-screen-ai-summary.js": "screen-ai-summary.js",
        "demo-screenshot-rename.js": "screenshot-rename.js",
        "demo-security-checklist.js": "security-checklist.js",
        "demo-share.js": "share.js",
        "demo-shortcuts.js": "shortcuts.js",
        "demo-snippets.js": "snippets.js",
        "demo-spaces.js": "spaces.js",
        "demo-system-metrics.js": "system-metrics.js",
        "demo-system-settings.js": "system-settings.js",
        "demo-url-router.js": "url-router.js",
        "demo-usb.js": "usb.js",
        "demo-weather.js": "weather.js",
        "demo-wifi.js": "wifi.js",
        "demo-window-grid.js": "window-grid.js",
        "demo-window-switcher.js": "window-switcher.js",
        "demo-windows.js": "windows.js",
    ]
}

public enum CatalogOverwrite: Equatable, Sendable {
    case unmodifiedBuiltIn
    case modified
}
