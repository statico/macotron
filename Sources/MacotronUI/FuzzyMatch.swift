// FuzzyMatch.swift — Simple fuzzy matching for search
import Foundation

public enum FuzzyMatch {
    /// Score a query against a target string. Higher = better match.
    /// Returns nil if the query doesn't match at all.
    public static func score(query: String, target: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let queryChars = Array(query.lowercased())
        let targetChars = Array(target.lowercased())

        var queryIdx = 0
        var score = 0
        var lastMatchIdx = -1

        for (i, char) in targetChars.enumerated() {
            if queryIdx < queryChars.count && char == queryChars[queryIdx] {
                // Consecutive match bonus
                if lastMatchIdx == i - 1 {
                    score += 10
                } else {
                    score += 5
                }
                // Start-of-word bonus
                if i == 0 || targetChars[i - 1] == " " || targetChars[i - 1] == "-" || targetChars[i - 1] == "_" {
                    score += 8
                }
                lastMatchIdx = i
                queryIdx += 1
            }
        }

        // All query characters must be found
        guard queryIdx == queryChars.count else { return nil }

        // Bonus for shorter targets (more specific matches)
        score += max(0, 20 - targetChars.count)

        return score
    }
}
