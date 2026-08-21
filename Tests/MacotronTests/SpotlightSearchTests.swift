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

    @Test("query uses Spotlight equality wildcards, not Cocoa LIKE")
    func queryFormat() {
        let q = SpotlightSearch.queryString("Notes")
        #expect(q?.contains("kMDItemDisplayName == '*Notes*'cd") == true)
        #expect(q?.contains("LIKE") != true)
    }

    @Test("query escapes Spotlight special characters")
    func escape() {
        let q = SpotlightSearch.queryString(#"a*"b"#)
        #expect(q?.contains(#"*a\*"b*"#) == true)
    }

    @Test("parse takes paths from mdfind output")
    func parse() {
        let rows = SpotlightSearch.parse("/tmp/Hello World.txt\n/Users/alex/Notes.md\n")
        #expect(rows.count == 2)
        #expect(rows[0]["path"] as? String == "/tmp/Hello World.txt")
        #expect(rows[0]["name"] as? String == "Hello World.txt")
        #expect(rows[1]["name"] as? String == "Notes.md")
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
