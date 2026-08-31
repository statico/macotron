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

    @Test("a name-prefix hit outranks a mid-name hit from a shallower path")
    func prefixBeatsMidName() {
        let out = "/Applications/Remote Desktop.app\n/Users/alex/Desktop\n"
        let rows = SpotlightSearch.parse(out, term: "deskt", home: "/Users/alex")
        #expect(rows[0]["path"] as? String == "/Users/alex/Desktop")
    }

    private func makeHome(_ folders: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macotron-home-\(UUID().uuidString)")
        for folder in folders {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        return dir
    }

    @Test("a slash query completes each path segment in turn")
    func pathCompletion() throws {
        let home = try makeHome(["dev/notes", "Desktop", "Documents"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.pathComplete("~/d/notes", home: home.path).first
            == home.appendingPathComponent("dev/notes").path)
        // No tilde means the same place, and a dead segment means no rows.
        #expect(SpotlightSearch.pathComplete("d/notes", home: home.path).first
            == home.appendingPathComponent("dev/notes").path)
        #expect(SpotlightSearch.pathComplete("~/zz/notes", home: home.path).isEmpty)
    }

    @Test("a trailing slash lists the folder's children")
    func trailingSlashLists() throws {
        let home = try makeHome(["dev/notes", "dev/tools"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.pathComplete("~/dev/", home: home.path) == [
            home.appendingPathComponent("dev/notes").path,
            home.appendingPathComponent("dev/tools").path,
        ])
    }

    @Test("a fuzzy query spans path segments")
    func fuzzySpansSegments() throws {
        let home = try makeHome(["Documents/3D Printing", "Downloads"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.fuzzy("doc3d", home: home.path).first
            == home.appendingPathComponent("Documents/3D Printing").path)
        // Slash queries and short queries stay with their own machinery.
        #expect(SpotlightSearch.fuzzy("a/b", home: home.path).isEmpty)
        #expect(SpotlightSearch.fuzzy("do", home: home.path).isEmpty)
        // A space in the query does not demand a space on the path.
        #expect(SpotlightSearch.fuzzy("doc 3d", home: home.path).first
            == home.appendingPathComponent("Documents/3D Printing").path)
    }

    @Test("dot and dot-dot walk instead of matching names")
    func dotSegments() throws {
        let home = try makeHome(["dev/notes", ".fzf.zsh"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.pathComplete("~/dev/./notes", home: home.path).first
            == home.appendingPathComponent("dev/notes").path)
        #expect(SpotlightSearch.pathComplete("~/dev/../dev/notes", home: home.path).first
            == home.appendingPathComponent("dev/notes").path)
        // ".." must not fuzzy-match dotfiles with two dots in their names.
        #expect(SpotlightSearch.pathComplete("~/..", home: home.path)
            == [(home.path as NSString).deletingLastPathComponent])
    }

    @Test("a scoped folder roots a relative path query")
    func scopedPathQuery() throws {
        let home = try makeHome(["project/src/main", "src"])
        defer { try? FileManager.default.removeItem(at: home) }
        let scoped = SpotlightSearch.pathComplete(
            "src/main", home: home.path, root: home.appendingPathComponent("project").path)
        #expect(scoped.first == home.appendingPathComponent("project/src/main").path)
    }

    @Test("a bare tilde-slash lists home")
    func tildeListsHome() throws {
        let home = try makeHome(["Desktop", "Documents"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.pathComplete("~/", home: home.path) == [
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Documents").path,
        ])
    }

    @Test("an exact name buried deep loses to the obvious shallow folder")
    func buriedExactLoses() {
        let out = "/Users/alex/Documents\n/Applications/tools/sdk/v6/firmware/help/doc\n"
        let rows = SpotlightSearch.parse(out, term: "doc", home: "/Users/alex")
        #expect(rows[0]["path"] as? String == "/Users/alex/Documents")
    }

    @Test("a bare tilde lists home")
    func bareTilde() throws {
        let home = try makeHome(["Desktop"])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SpotlightSearch.pathComplete("~", home: home.path)
            == [home.appendingPathComponent("Desktop").path])
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
