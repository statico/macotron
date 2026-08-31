import Testing
@testable import Modules
import MacotronEngine
import MacotronUI

@Suite("LauncherMatch")
struct LauncherMatchTests {
    @Test("empty query is a zero-score match")
    func empty() {
        #expect(FuzzyMatch.best(query: "", targets: ["Shopping", "Notes"]) == 0)
    }

    @Test("matches title or subtitle")
    func either() {
        #expect(FuzzyMatch.best(query: "shop", targets: ["Shopping list", "Personal"]) != nil)
        #expect(FuzzyMatch.best(query: "pers", targets: ["Shopping list", "Personal"]) != nil)
        #expect(FuzzyMatch.best(query: "xyz", targets: ["Shopping list", "Personal"]) == nil)
    }
}

@Suite("NotesList")
struct NotesListTests {
    @Test("parses one block per folder")
    func parseFolders() {
        let text = "Personal\nid-1\tid-2\nShopping\tIdeas\u{01}Work\nid-3\nPlan\u{01}Empty\n\n"
        #expect(NotesList.parseFolders(text) == [
            NoteRecord(id: "id-1", title: "Shopping", folder: "Personal"),
            NoteRecord(id: "id-2", title: "Ideas", folder: "Personal"),
            NoteRecord(id: "id-3", title: "Plan", folder: "Work"),
        ])
    }

    @Test("escapes AppleScript strings")
    func escape() {
        #expect(NotesList.escape("a\"b\\c") == "a\\\"b\\\\c")
    }

    @Test("newlines cannot break out of AppleScript string literals")
    func escapeNewlines() {
        #expect(NotesList.escape("a\nb") == "a\" & return & \"b")
        #expect(NotesList.escape("a\rb") == "a\" & return & \"b")
        #expect(NotesList.escape("a\r\nb") == "a\" & return & \"b")
    }

    @Test("hides Recently Deleted")
    func hidesDeleted() {
        let rows = NotesList.parseFolders("Notes\nid-1\nKeep\u{01}Recently Deleted\nid-2\nGone")
        #expect(NotesList.visible(rows) == [
            NoteRecord(id: "id-1", title: "Keep", folder: "Notes"),
        ])
        #expect(NotesList.isDeleted("Recently Deleted"))
        #expect(!NotesList.isDeleted("Notes"))
    }
}
