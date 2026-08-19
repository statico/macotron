import Foundation

public struct LauncherFavorites: Equatable, Sendable {
    public private(set) var ids: [String]

    public init(ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    public mutating func toggle(_ id: String) {
        guard !id.isEmpty else { return }
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    public static func load(from object: Any?) -> LauncherFavorites {
        if let ids = object as? [String] {
            return LauncherFavorites(ids: ids)
        }
        if let ids = object as? [Any] {
            return LauncherFavorites(ids: ids.compactMap { $0 as? String })
        }
        return LauncherFavorites()
    }

    public func jsonObject() -> [String] {
        ids
    }
}
