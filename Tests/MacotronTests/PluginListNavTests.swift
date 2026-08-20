import Testing
@testable import MacotronUI

@Suite("PluginListNav")
struct PluginListNavTests {
    let files = ["a.js", "b.js", "c.js"]

    @Test("down moves to the next plugin")
    func down() {
        #expect(PluginListNav.neighbor(of: "a.js", in: files, delta: 1) == "b.js")
        #expect(PluginListNav.neighbor(of: "c.js", in: files, delta: 1) == "c.js")
    }

    @Test("up moves to the previous plugin")
    func up() {
        #expect(PluginListNav.neighbor(of: "b.js", in: files, delta: -1) == "a.js")
        #expect(PluginListNav.neighbor(of: "a.js", in: files, delta: -1) == "a.js")
    }

    @Test("no selection starts at the first or last plugin")
    func emptySelection() {
        #expect(PluginListNav.neighbor(of: nil, in: files, delta: 1) == "a.js")
        #expect(PluginListNav.neighbor(of: nil, in: files, delta: -1) == "c.js")
    }
}

@Suite("MacotronRepo")
struct MacotronRepoTests {
    @Test("points at the public GitHub repo")
    func url() {
        #expect(MacotronRepo.url.absoluteString == "https://github.com/statico/macotron")
    }
}
