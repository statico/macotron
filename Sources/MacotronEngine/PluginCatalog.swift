import Foundation

public struct CatalogPlugin: Equatable, Identifiable, Sendable {
    public var filename: String
    public var kind: String
    public var highlighted: Bool
    public var category: String
    public var title: String
    public var description: String
    public var permissions: [Permission]
    public var source: String
    public var bundleHash: String
    public var fileURL: URL

    public var id: String { filename }
    public var isStock: Bool { kind == "stock" }

    public init(
        filename: String,
        kind: String,
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
        self.kind = kind
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
                kind: row["kind"] as? String ?? "demo",
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
            if lhs.isStock != rhs.isStock { return lhs.isStock && !rhs.isStock }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public static func overwriteKind(existingHash: String?, bundledHash: String) -> CatalogOverwrite? {
        guard let existingHash else { return nil }
        if existingHash == bundledHash { return .unmodifiedStock }
        return .modified
    }
}

public enum CatalogOverwrite: Equatable, Sendable {
    case unmodifiedStock
    case modified
}
