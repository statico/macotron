import Testing
@testable import Modules
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
    @Test("parses TSV from AppleScript")
    func parse() {
        let rows = NotesList.parse("id-1\tShopping\tPersonal\nid-2\tIdeas\n")
        #expect(rows == [
            NoteRecord(id: "id-1", title: "Shopping", folder: "Personal"),
            NoteRecord(id: "id-2", title: "Ideas", folder: ""),
        ])
    }

    @Test("escapes AppleScript strings")
    func escape() {
        #expect(NotesList.escape("a\"b\\c") == "a\\\"b\\\\c")
    }
}
