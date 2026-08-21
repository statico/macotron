// FuzzyMatchTests.swift — Tests for fuzzy matching scoring
import Testing
@testable import MacotronUI

@MainActor
@Suite("FuzzyMatch Tests")
struct FuzzyMatchTests {

    @Test("nil unless every query character is found in order")
    func noMatch() {
        #expect(FuzzyMatch.score(query: "xyz", target: "abc") == nil)
        #expect(FuzzyMatch.score(query: "abz", target: "abcdef") == nil)
        #expect(FuzzyMatch.score(query: "abcdefgh", target: "abc") == nil)
        #expect(FuzzyMatch.score(query: "aaa", target: "abc") == nil)
    }

    @Test("empty query scores zero rather than failing")
    func emptyQuery() {
        #expect(FuzzyMatch.score(query: "", target: "anything") == 0)
        #expect(FuzzyMatch.score(query: "", target: "") == 0)
    }

    @Test("case is ignored, and does not change the score")
    func caseInsensitive() {
        let lower = FuzzyMatch.score(query: "test", target: "testing")
        #expect(lower != nil)
        #expect(FuzzyMatch.score(query: "TEST", target: "TESTING") == lower)
        #expect(FuzzyMatch.score(query: "TeSt", target: "TeStInG") == lower)
    }

    @Test("a prefix match beats the same run mid-word")
    func prefixBeatsMidWord() throws {
        let prefix = try #require(FuzzyMatch.score(query: "saf", target: "safari"))
        let mid = try #require(FuzzyMatch.score(query: "saf", target: "unsafari"))
        #expect(prefix > mid)
    }

    @Test("a match after a separator beats one inside a word")
    func wordBoundaryBeatsMidWord() throws {
        let boundary = try #require(FuzzyMatch.score(query: "win", target: "my-window"))
        let midWord = try #require(FuzzyMatch.score(query: "win", target: "twinning"))
        #expect(boundary > midWord)
    }

    /// Same-length targets, both matching at index 0, so only the consecutive
    /// bonus can separate them.
    @Test("consecutive characters beat scattered ones")
    func consecutiveBeatsScattered() throws {
        let consecutive = try #require(FuzzyMatch.score(query: "abc", target: "abcdef"))
        let scattered = try #require(FuzzyMatch.score(query: "abc", target: "axbxcx"))
        #expect(consecutive > scattered)
    }

    @Test("a shorter target beats a longer one")
    func shorterTargetWins() throws {
        let short = try #require(FuzzyMatch.score(query: "a", target: "a"))
        let long = try #require(FuzzyMatch.score(query: "a", target: "a" + String(repeating: "x", count: 30)))
        #expect(short > long)
    }

    @Test("app-style queries rank the intended app first")
    func ranking() throws {
        let safari = try #require(FuzzyMatch.score(query: "saf", target: "Safari"))
        for other in ["System Safety", "is a safari file"] {
            if let score = FuzzyMatch.score(query: "saf", target: other) {
                #expect(safari >= score, "Safari should outrank \(other)")
            }
        }
        #expect(FuzzyMatch.score(query: "ff", target: "Firefox") != nil)
        #expect(FuzzyMatch.score(query: "ff", target: "Chrome") == nil)
    }
}
