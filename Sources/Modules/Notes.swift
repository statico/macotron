import Foundation

struct NoteRecord: Equatable {
    var id: String
    var title: String
    var folder: String
}

enum NotesList {
    /// One block per folder, blocks split by ASCII 1: folder name, then the
    /// tab-joined note ids, then the tab-joined titles.
    static func parseFolders(_ text: String) -> [NoteRecord] {
        text.split(separator: "\u{01}").flatMap { block -> [NoteRecord] in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { return [] }
            let folder = String(lines[0])
            let ids = lines[1].split(separator: "\t", omittingEmptySubsequences: false)
            let titles = lines[2].split(separator: "\t", omittingEmptySubsequences: false)
            return zip(ids, titles).compactMap { id, title in
                id.isEmpty ? nil : NoteRecord(id: String(id), title: String(title), folder: folder)
            }
        }
    }

    static func visible(_ notes: [NoteRecord]) -> [NoteRecord] {
        notes.filter { !isDeleted($0.folder) }
    }

    static func isDeleted(_ folder: String) -> Bool {
        folder.localizedCaseInsensitiveContains("Recently Deleted")
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\" & return & \"")
            .replacingOccurrences(of: "\r", with: "\" & return & \"")
            .replacingOccurrences(of: "\n", with: "\" & return & \"")
    }
}
