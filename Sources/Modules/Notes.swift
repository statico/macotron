import Foundation

struct NoteRecord: Equatable {
    var id: String
    var title: String
    var folder: String
}

enum NotesList {
    static func parse(_ text: String) -> [NoteRecord] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            return NoteRecord(
                id: parts[0],
                title: parts[1],
                folder: parts.count > 2 ? parts[2] : ""
            )
        }
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
