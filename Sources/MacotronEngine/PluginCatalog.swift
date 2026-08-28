import Foundation

public struct CatalogPlugin: Equatable, Identifiable, Sendable {
    public var filename: String
    public var highlighted: Bool
    public var title: String
    public var description: String
    public var permissions: [Permission]
    public var source: String
    public var bundleHash: String
    /// Where the bytes sit on this Mac. Nil for a plugin downloaded from a
    /// community repository, which has no local copy until it is installed.
    public var fileURL: URL?
    /// Set only for a plugin that came off GitHub.
    public var origin: CommunityOrigin?

    public var id: String { origin?.repo ?? filename }

    public init(
        filename: String,
        highlighted: Bool,
        title: String,
        description: String,
        permissions: [Permission],
        source: String,
        bundleHash: String,
        fileURL: URL? = nil,
        origin: CommunityOrigin? = nil
    ) {
        self.filename = filename
        self.highlighted = highlighted
        self.title = title
        self.description = description
        self.permissions = permissions
        self.source = source
        self.bundleHash = bundleHash
        self.fileURL = fileURL
        self.origin = origin
    }
}

public enum PluginCatalog {
    public static func load(bundle: Bundle = .main) -> [CatalogPlugin] {
        let jsonURL = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Catalog")
            ?? bundle.url(forResource: "catalog", withExtension: "json")
        guard let jsonURL else { return [] }
        return load(jsonURL: jsonURL)
    }

    /// The bundled catalog is the Catalog folder itself: every `.js` beside
    /// catalog.json is on offer, and the JSON only names the featured few.
    public static func load(jsonURL: URL) -> [CatalogPlugin] {
        let catalogDir = jsonURL.deletingLastPathComponent()
        let data = (try? Data(contentsOf: jsonURL)) ?? Data()
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let highlighted = Set(root?["highlighted"] as? [String] ?? [])
        let filenames = (try? FileManager.default.contentsOfDirectory(atPath: catalogDir.path)) ?? []
        return filenames.filter { $0.hasSuffix(".js") }.compactMap { filename in
            let fileURL = catalogDir.appending(path: filename)
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
            let header = PluginHeader.parse(source)
            return CatalogPlugin(
                filename: filename,
                highlighted: highlighted.contains(filename),
                title: header.title ?? String(filename.dropLast(3)),
                description: header.description ?? "",
                permissions: header.permissions.compactMap(Permission.init(rawValue:)),
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
    /// stay put because `screen-effects.js` replaced all three, and
    /// `demo-browser-profiles.js` and `demo-url-router.js` because
    /// `browser-picker.js` replaced both.
    public static let legacyRenames: [String: String] = Dictionary(
        uniqueKeysWithValues: """
        ai-chat appearance audio batch-rename battery brightness browser-picker calculator \
        calendar clipboard-history clipboard-image color-picker cpu-graph datetime devutils \
        disk-usage fan file-search focus-idle gestures heic-to-jpeg hid hyper icon-rainbow \
        idle layouts lock-screen lorem meeting-overlay meetings notes now-playing ocr \
        plain-paste pomodoro power present-mode qr record regex screen-ai-summary \
        screenshot-rename security-checklist share shortcuts snippets spaces system-metrics \
        system-settings usb weather wifi window-grid window-switcher windows
        """.split(whereSeparator: \.isWhitespace).map { ("demo-\($0).js", "\($0).js") }
    )
}

public enum CatalogOverwrite: Equatable, Sendable {
    case unmodifiedBuiltIn
    case modified
}
