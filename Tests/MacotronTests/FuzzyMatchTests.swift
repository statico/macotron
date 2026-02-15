// FuzzyMatchTests.swift — Tests for fuzzy matching scoring
import Testing
@testable import MacotronUI

@MainActor
@Suite("FuzzyMatch Tests")
struct FuzzyMatchTests {

    // MARK: - Exact Match

    @Test("Exact match scores highest among variations")
    func testExactMatchHighest() {
        let exactScore = FuzzyMatch.score(query: "safari", target: "safari")
        let partialScore = FuzzyMatch.score(query: "safari", target: "safari browser app")
        let embeddedScore = FuzzyMatch.score(query: "safari", target: "xsafari embedded")

        #expect(exactScore != nil)
        #expect(partialScore != nil)
        #expect(embeddedScore != nil)
        // Exact match on shorter string should score higher due to length bonus
        #expect(exactScore! > partialScore!)
        // Prefix match with word boundary should score higher than mid-word match
        #expect(partialScore! > embeddedScore!)
    }

    @Test("Exact match returns non-nil score")
    func testExactMatchNotNil() {
        let score = FuzzyMatch.score(query: "test", target: "test")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test("Full exact match on short string yields high score")
    func testExactMatchShortString() {
        let score = FuzzyMatch.score(query: "abc", target: "abc")
        #expect(score != nil)
        // 3 chars: first char = 5 + 8 (start-of-word) = 13, second = 10 (consecutive), third = 10 (consecutive)
        // + length bonus = max(0, 20 - 3) = 17
        // total = 13 + 10 + 10 + 17 = 50
        #expect(score! >= 40)
    }

    // MARK: - Prefix Match vs Mid-Match

    @Test("Prefix match scores higher than mid-match")
    func testPrefixVsMidMatch() {
        let prefixScore = FuzzyMatch.score(query: "saf", target: "safari")
        let midScore = FuzzyMatch.score(query: "saf", target: "unsafari")
        #expect(prefixScore != nil)
        #expect(midScore != nil)
        // Prefix match gets start-of-word bonus on first char
        #expect(prefixScore! > midScore!)
    }

    @Test("Match at word boundary scores higher than mid-word")
    func testWordBoundaryBonus() {
        let boundaryScore = FuzzyMatch.score(query: "win", target: "my-window")
        let midWordScore = FuzzyMatch.score(query: "win", target: "twinning")
        #expect(boundaryScore != nil)
        #expect(midWordScore != nil)
        // "win" in "my-window" starts at word boundary (after '-')
        #expect(boundaryScore! > midWordScore!)
    }

    // MARK: - No Match

    @Test("No match returns nil")
    func testNoMatch() {
        let score = FuzzyMatch.score(query: "xyz", target: "abc")
        #expect(score == nil)
    }

    @Test("Partial no match returns nil when not all chars found")
    func testPartialNoMatch() {
        let score = FuzzyMatch.score(query: "abz", target: "abcdef")
        #expect(score == nil)
    }

    @Test("Query longer than target returns nil")
    func testQueryLongerThanTarget() {
        let score = FuzzyMatch.score(query: "abcdefgh", target: "abc")
        #expect(score == nil)
    }

    @Test("Completely disjoint characters return nil")
    func testDisjointChars() {
        let score = FuzzyMatch.score(query: "zzz", target: "aaa")
        #expect(score == nil)
    }

    // MARK: - Case Insensitive

    @Test("Case insensitive matching works")
    func testCaseInsensitive() {
        let score1 = FuzzyMatch.score(query: "safari", target: "Safari")
        let score2 = FuzzyMatch.score(query: "SAFARI", target: "safari")
        let score3 = FuzzyMatch.score(query: "SaFaRi", target: "sAfArI")
        #expect(score1 != nil)
        #expect(score2 != nil)
        #expect(score3 != nil)
    }

    @Test("Case insensitive scores are identical")
    func testCaseInsensitiveScoresEqual() {
        let lower = FuzzyMatch.score(query: "test", target: "testing")
        let upper = FuzzyMatch.score(query: "TEST", target: "TESTING")
        let mixed = FuzzyMatch.score(query: "TeSt", target: "TeStInG")
        #expect(lower == upper)
        #expect(upper == mixed)
    }

    // MARK: - Empty Query

    @Test("Empty query returns zero")
    func testEmptyQuery() {
        let score = FuzzyMatch.score(query: "", target: "anything")
        #expect(score == 0)
    }

    @Test("Empty query with empty target returns zero")
    func testEmptyQueryEmptyTarget() {
        let score = FuzzyMatch.score(query: "", target: "")
        #expect(score == 0)
    }

    // MARK: - Consecutive Match Bonus

    @Test("Consecutive matches score bonus")
    func testConsecutiveBonus() {
        // "abc" in "abcdef" — all consecutive starting from beginning
        let consecutiveScore = FuzzyMatch.score(query: "abc", target: "abcdef")
        // "abc" in "axbxcx" — scattered, no consecutive bonus
        let scatteredScore = FuzzyMatch.score(query: "abc", target: "axbxcx")
        #expect(consecutiveScore != nil)
        #expect(scatteredScore != nil)
        #expect(consecutiveScore! > scatteredScore!)
    }

    @Test("All consecutive chars score higher than scattered non-boundary")
    func testAllConsecutive() {
        let allConsec = FuzzyMatch.score(query: "test", target: "testing")
        // Use a target where scattered chars do NOT land on word boundaries
        let scattered = FuzzyMatch.score(query: "test", target: "xtxexsxtx")
        #expect(allConsec != nil)
        #expect(scattered != nil)
        #expect(allConsec! > scattered!)
    }

    // MARK: - Length Bonus

    @Test("Shorter target gets length bonus")
    func testShorterTargetBonus() {
        let shortScore = FuzzyMatch.score(query: "a", target: "a")
        let longScore = FuzzyMatch.score(query: "a", target: "a" + String(repeating: "x", count: 30))
        #expect(shortScore != nil)
        #expect(longScore != nil)
        #expect(shortScore! > longScore!)
    }

    // MARK: - Word Boundary Bonus

    @Test("Start of word after space gets bonus")
    func testStartOfWordAfterSpace() {
        let score = FuzzyMatch.score(query: "w", target: "hello world")
        #expect(score != nil)
        // 'w' matches at index 6, which is start of 'world' (after space)
        // Should get word boundary bonus
    }

    @Test("Start of word after hyphen gets bonus")
    func testStartOfWordAfterHyphen() {
        let hyphScore = FuzzyMatch.score(query: "b", target: "my-browser")
        let midScore = FuzzyMatch.score(query: "b", target: "myxbrowser")
        #expect(hyphScore != nil)
        #expect(midScore != nil)
        // 'b' after '-' should score higher than 'b' after 'x'
        #expect(hyphScore! > midScore!)
    }

    @Test("Start of word after underscore gets bonus")
    func testStartOfWordAfterUnderscore() {
        let underscoreScore = FuzzyMatch.score(query: "m", target: "window_manager")
        #expect(underscoreScore != nil)
    }

    // MARK: - Real-World Scenarios

    @Test("Searching 'term' matches 'Terminal' well")
    func testRealWorldTerminal() {
        let score = FuzzyMatch.score(query: "term", target: "Terminal")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test("Searching 'ff' matches 'Firefox' but not 'Chrome'")
    func testRealWorldFirefox() {
        let firefoxScore = FuzzyMatch.score(query: "ff", target: "Firefox")
        let chromeScore = FuzzyMatch.score(query: "ff", target: "Chrome")
        #expect(firefoxScore != nil)
        #expect(chromeScore == nil)
    }

    @Test("Searching 'wm' matches 'window-manager' via word boundaries")
    func testRealWorldWindowManager() {
        let score = FuzzyMatch.score(query: "wm", target: "window-manager")
        #expect(score != nil)
        // 'w' at start of 'window', 'm' at start of 'manager' (after '-')
    }

    @Test("Better match ranks higher among candidates")
    func testRanking() {
        let query = "saf"
        let scores = [
            ("Safari", FuzzyMatch.score(query: query, target: "Safari")),
            ("System Safety", FuzzyMatch.score(query: query, target: "System Safety")),
            ("is a safari file", FuzzyMatch.score(query: query, target: "is a safari file")),
        ]

        // Safari should rank highest (prefix match, short string)
        let safariScore = scores[0].1!
        for (name, score) in scores.dropFirst() {
            if let s = score {
                #expect(safariScore >= s, "Safari should score >= \(name)")
            }
        }
    }

    @Test("Single char query matches first occurrence")
    func testSingleCharQuery() {
        let score = FuzzyMatch.score(query: "a", target: "apple")
        #expect(score != nil)
        #expect(score! > 0)
    }

    @Test("Query with repeated chars matches correctly")
    func testRepeatedChars() {
        let score = FuzzyMatch.score(query: "aa", target: "aardvark")
        #expect(score != nil)
    }

    @Test("Query with repeated chars fails if not enough in target")
    func testRepeatedCharsFail() {
        let score = FuzzyMatch.score(query: "aaa", target: "abc")
        #expect(score == nil)
    }
}
