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
        if existingHash == bundledHash { return .unmodifiedStock }
        return .modified
    }

    private static let consolidationLegacyNames: Set<String> = [
        "demo-night-vision.js",
        "demo-gamma-black.js",
        "demo-display-modes.js",
    ]

    public static func legacyRenames(bundle: Bundle = .main) -> [String: String] {
        legacyRenames(from: load(bundle: bundle))
    }

    public static func legacyRenames(jsonURL: URL) -> [String: String] {
        legacyRenames(from: load(jsonURL: jsonURL))
    }

    private static func legacyRenames(from plugins: [CatalogPlugin]) -> [String: String] {
        var renames: [String: String] = [:]
        for plugin in plugins {
            let filename = plugin.filename
            let oldName: String
            let newName: String
            if filename.hasPrefix("demo-") {
                oldName = filename
                newName = String(filename.dropFirst(5))
            } else {
                newName = filename
                oldName = "demo-" + newName
            }
            guard oldName != newName, !consolidationLegacyNames.contains(oldName) else { continue }
            renames[oldName] = newName
        }
        return renames
    }
}

public enum CatalogOverwrite: Equatable, Sendable {
    case unmodifiedStock
    case modified
}
