// WindowRestore.swift — match saved layout entries to a window snapshot
import Foundation

enum WindowRestore {
    struct Window: Equatable, Sendable {
        var id: Int32
        var app: String
        var title: String
        var bundleID: String?
    }

    struct Entry: Equatable, Sendable {
        var app: String
        var title: String?
        var bundleID: String?
    }

    static func match(_ windows: [Window], _ entry: Entry) -> Int32? {
        let candidates = windows.filter { appMatches($0, entry) }
        guard !candidates.isEmpty else { return nil }
        if let title = entry.title, !title.isEmpty {
            if let exact = candidates.first(where: { $0.title == title }) {
                return exact.id
            }
            if let prefix = candidates.first(where: { $0.title.hasPrefix(title) }) {
                return prefix.id
            }
        }
        return candidates.first?.id
    }

    private static func appMatches(_ window: Window, _ entry: Entry) -> Bool {
        if let want = nonempty(entry.bundleID), let have = nonempty(window.bundleID) {
            return want == have
        }
        return window.app.caseInsensitiveCompare(entry.app) == .orderedSame
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
