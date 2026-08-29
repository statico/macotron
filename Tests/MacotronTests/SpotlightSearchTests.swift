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
        let rows = SpotlightSearch.parse(out)
        #expect(rows.count == 2)
        // Neither path exists, so both rank as never-used and the path breaks the
        // tie. mdfind's own order is not stable between runs of the same search.
        #expect(rows[0]["path"] as? String == "/Users/alex/Notes.md")
        #expect(rows[0]["name"] as? String == "Notes.md")
        #expect(rows[1]["name"] as? String == "Hello World.txt")
        #expect(SpotlightSearch.parse(out).map { $0["path"] as? String } ==
                rows.map { $0["path"] as? String })
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
}
