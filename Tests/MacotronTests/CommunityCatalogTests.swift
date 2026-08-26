import Foundation
import Testing
@testable import MacotronEngine

@Suite("Community catalog")
struct CommunityCatalogTests {
    @Test("repository names become plain plugin filenames")
    func filenames() {
        #expect(CommunityCatalog.filename(forRepo: "macotron-weather") == "weather.js")
        #expect(CommunityCatalog.filename(forRepo: "Window-Grid") == "window-grid.js")
        #expect(CommunityCatalog.filename(forRepo: "tidy-plugin") == "tidy.js")
        #expect(CommunityCatalog.filename(forRepo: "notes.js") == "notes.js")
        // Nothing survives sanitising, so the repository name is the fallback.
        #expect(CommunityCatalog.filename(forRepo: "!!!") == "!!!.js")
    }

    @Test("download probes the repository name first")
    func candidateOrder() {
        let entry = CommunityEntry(
            repo: "statico/macotron-weather", title: "Weather", summary: "",
            stars: 3, pushedAt: nil, defaultBranch: "main",
            homepage: URL(string: "https://github.com/statico/macotron-weather")!
        )
        #expect(CommunityCatalog.candidates(for: entry)
            == ["macotron-weather.js", "weather.js", "plugin.js", "index.js"])
        #expect(entry.filename == "weather.js")
        #expect(entry.owner == "statico")
    }

    @Test("search results drop archived and malformed rows")
    func parseSearch() throws {
        let payload = """
        {"items": [
          {"full_name": "a/macotron-notes", "name": "macotron-notes", "description": "Take notes.",
           "stargazers_count": 12, "pushed_at": "2026-08-01T10:00:00Z",
           "default_branch": "main", "html_url": "https://github.com/a/macotron-notes"},
          {"full_name": "b/dead", "name": "dead", "archived": true, "default_branch": "main",
           "html_url": "https://github.com/b/dead"},
          {"name": "no-full-name", "default_branch": "main", "html_url": "https://x"}
        ]}
        """
        let entries = CommunityCatalog.parse(searchPayload: Data(payload.utf8))
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.repo == "a/macotron-notes")
        #expect(entry.title == "Notes")
        #expect(entry.stars == 12)
        #expect(entry.pushedAt != nil)
    }

    @Test("rate limiting is reported as itself")
    func rateLimit() {
        let url = URL(string: "https://api.github.com/search/repositories")!
        let limited = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!
        #expect(throws: CommunityCatalogError.rateLimited) {
            try CommunityCatalog.check(limited)
        }
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        #expect(throws: Never.self) { try CommunityCatalog.check(ok) }
    }
}

@Suite("Plugin blocklist")
@MainActor
struct PluginBlocklistTests {
    @Test("blocked bytes never match the trust ledger")
    func blockedBeatsApproval() {
        let source = "macotron.plugin({ title: 'Bad' })"
        let store = MemoryHashStore()
        let previous = PluginTrust.store
        PluginTrust.store = store
        defer {
            PluginTrust.store = previous
            PluginBlocklist.reset(to: [:])
        }

        PluginBlocklist.reset(to: [:])
        PluginTrust.approve(filename: "bad.js", source: source)
        #expect(PluginTrust.matches(filename: "bad.js", source: source))

        PluginBlocklist.reset(to: [PluginHash.sha256(source: source): "Steals the clipboard."])
        #expect(!PluginTrust.matches(filename: "bad.js", source: source))
        #expect(PluginBlocklist.reason(hash: PluginHash.sha256(source: source)) != nil)
    }

    @Test("the published file parses, uppercase hashes included")
    func parseFile() {
        let data = Data("""
        {"blocked": [
          {"sha256": "AABB", "reason": "Nope."},
          {"sha256": "ccdd"},
          {"reason": "no hash"}
        ]}
        """.utf8)
        let parsed = PluginBlocklist.parse(data)
        #expect(parsed?.count == 2)
        #expect(parsed?["aabb"] == "Nope.")
        #expect(parsed?["ccdd"] == "Blocked by Macotron.")
        #expect(PluginBlocklist.parse(Data("not json".utf8)) == nil)
    }
}
