import Foundation
import Testing
@testable import Modules

@Suite("SpotlightSearch")
struct SpotlightSearchTests {
    @Test("empty query does not search")
    func emptyQuery() {
        #expect(SpotlightSearch.queryString("") == nil)
        #expect(SpotlightSearch.queryString("   ") == nil)
        #expect(SpotlightSearch.parse("").isEmpty)
    }

    @Test("query seeks the index by prefix instead of scanning it")
    func queryFormat() {
        let q = SpotlightSearch.queryString("Notes")
        // A leading wildcard is the 100x slower shape; `w` keeps mid-name words matching.
        #expect(q?.contains("kMDItemFSName == 'Notes*'cw") == true)
        #expect(q?.contains("'*Notes") != true)
        #expect(q?.contains("LIKE") != true)
    }

    @Test("query escapes Spotlight special characters")
    func escape() {
        let q = SpotlightSearch.queryString(#"a*"b"#)
        #expect(q?.contains(#"a\*"b*"#) == true)
    }

    @Test("parse takes paths from mdfind output, in a stable order")
    func parse() {
        let out = "/tmp/Hello World.txt\n/Users/alex/Notes.md\n"
        let rows = SpotlightSearch.parse(out, term: "note", home: "/Users/alex")
        #expect(rows.count == 2)
        // Home beats /tmp, and the path breaks any remaining tie: mdfind's own
        // order is not stable between runs of the same search.
        #expect(rows[0]["path"] as? String == "/Users/alex/Notes.md")
        #expect(rows[0]["name"] as? String == "Notes.md")
        #expect(rows[1]["name"] as? String == "Hello World.txt")
        #expect(SpotlightSearch.parse(out, term: "note", home: "/Users/alex").map { $0["path"] as? String } ==
                rows.map { $0["path"] as? String })
    }

    @Test("the obvious folder outranks a deeper one with the same name")
    func shortestPathWins() {
        let out = """
            /Users/alex/dev/app/node_modules/downloads/index.js
            /Users/alex/dev/downloads
            /Users/alex/Downloads
            /Library/Caches/downloads
            """
        let rows = SpotlightSearch.parse(out, term: "downloads", home: "/Users/alex")
        #expect(rows.map { $0["path"] as? String } == [
            "/Users/alex/Downloads",
            "/Users/alex/dev/downloads",
            "/Library/Caches/downloads",
            "/Users/alex/dev/app/node_modules/downloads/index.js",
        ])
    }

    @Test("an exact name wins even from a deeper path")
    func exactNameLeads() {
        let out = "/Users/alex/Budget notes.txt\n/Users/alex/work/2026/Budget\n"
        let rows = SpotlightSearch.parse(out, term: "budget", home: "/Users/alex")
        #expect(rows[0]["path"] as? String == "/Users/alex/work/2026/Budget")
    }

    @Test("dot directories sink below everything they would otherwise outrank")
    func hiddenSinks() {
        let out = "/Users/alex/.cache/report\n/Users/alex/work/notes/2026/report\n"
        let rows = SpotlightSearch.parse(out, term: "report", home: "/Users/alex")
        #expect(rows[0]["path"] as? String == "/Users/alex/work/notes/2026/report")
    }

    @Test("kind pdf appears in the query as *.pdf")
    func kindPdf() {
        let q = SpotlightSearch.queryString("Notes", kind: "pdf")
        #expect(q?.contains("*.pdf") == true)
    }

    @Test("empty kind does not add FSName extension clause")
    func emptyKind() {
        let q = SpotlightSearch.queryString("Notes", kind: "")
        #expect(q == SpotlightSearch.queryString("Notes"))
        #expect(q?.contains("*.") != true)
    }

    @Test("the top of a home directory is scanned, since Spotlight will not return it")
    func shallowRootsAreScanned() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macotron-shallow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Desktop"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let found = SpotlightSearch.shallow("desk", roots: [dir.path])
        #expect(found == [dir.appendingPathComponent("Desktop").path])
        #expect(SpotlightSearch.shallow("hid", roots: [dir.path]).isEmpty)
    }

    @Test("a scanned folder is not repeated when Spotlight also returns it")
    func extraIsDeduped() {
        let rows = SpotlightSearch.parse(
            "/Users/alex/Desktop\n", extra: ["/Users/alex/Desktop"],
            term: "desktop", home: "/Users/alex")
        #expect(rows.count == 1)
    }
}
