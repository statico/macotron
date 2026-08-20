import Foundation
import Testing
@testable import Modules

@Suite("URLRoute")
struct URLRouteTests {
    @Test("exact host matches")
    func exactHost() {
        #expect(URLRoute.pick([("https", "youtube.com")], url: u("https://youtube.com/watch")) == .match("youtube.com"))
    }

    @Test("suffix host matches rule")
    func suffixHost() {
        #expect(URLRoute.pick([("https", "youtube.com")], url: u("https://www.youtube.com/watch")) == .match("youtube.com"))
        #expect(URLRoute.pick([("https", "youtube.com")], url: u("https://m.youtube.com/watch")) == .match("youtube.com"))
    }

    @Test("exact host beats suffix")
    func exactBeatsSuffix() {
        let rules = [("https", "youtube.com"), ("https", "www.youtube.com")]
        #expect(URLRoute.pick(rules, url: u("https://www.youtube.com/watch")) == .match("www.youtube.com"))
    }

    @Test("longest suffix wins")
    func longestSuffix() {
        let rules = [("https", "com"), ("https", "google.com"), ("https", "mail.google.com")]
        #expect(URLRoute.pick(rules, url: u("https://mail.google.com/mail")) == .match("mail.google.com"))
    }

    @Test("www rule does not match the bare host")
    func suffixIsOneWay() {
        #expect(URLRoute.pick([("https", "www.youtube.com")], url: u("https://youtube.com/watch")) == .fallback)
    }

    @Test("wildcard when no host matches")
    func wildcard() {
        #expect(URLRoute.pick([("https", "*")], url: u("https://example.com/")) == .wildcard)
        #expect(URLRoute.pick([("https", "youtube.com"), ("https", "*")], url: u("https://example.com/")) == .wildcard)
    }

    @Test("host match beats wildcard")
    func hostBeatsWildcard() {
        let rules = [("https", "*"), ("https", "youtube.com")]
        #expect(URLRoute.pick(rules, url: u("https://www.youtube.com/watch")) == .match("youtube.com"))
    }

    @Test("no rules is fallback")
    func noRules() {
        #expect(URLRoute.pick([], url: u("https://example.com/")) == .fallback)
    }

    @Test("scheme must match")
    func schemeMustMatch() {
        #expect(URLRoute.pick([("https", "youtube.com")], url: u("http://youtube.com/watch")) == .fallback)
        #expect(URLRoute.pick([("https", "*")], url: u("http://example.com/")) == .fallback)
        #expect(URLRoute.pick([("mailto", "*")], url: u("mailto:you@example.com")) == .wildcard)
    }

    @Test("host match is case insensitive")
    func caseInsensitive() {
        #expect(URLRoute.pick([("HTTPS", "YouTube.com")], url: u("https://WWW.YOUTUBE.COM/watch")) == .match("YouTube.com"))
    }
}

private func u(_ string: String) -> URL {
    URL(string: string)!
}
