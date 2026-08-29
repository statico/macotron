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

        // Typing the beginning of a name is the least ambiguous thing a person
        // can do, and it has to beat the bonuses above: without this, "applic"
        // ranked the contact "Apple Inc." over the folder "Applications",
        // because the short name and its second word-start out-scored six
        // letters landing in a row.
        if targetChars.starts(with: queryChars) {
            score += 40
        }

        return score
    }

    /// Highest score across title/subtitle/etc. Empty query matches everything.
    public static func best(query: String, targets: [String]) -> Int? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return 0 }
        return targets.filter { !$0.isEmpty }.compactMap { score(query: q, target: $0) }.max()
    }

    /// Items whose targets match `query`, best score first. An empty query keeps
    /// the input order; non-matches are dropped. `tieBreak` orders equal scores.
    public static func rank<T>(
        _ items: [T],
        query: String,
        targets: (T) -> [String],
        tieBreak: (T, T) -> Bool = { _, _ in false }
    ) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items
            .compactMap { item in best(query: q, targets: targets(item)).map { (item, $0) } }
            .sorted { $0.1 == $1.1 ? tieBreak($0.0, $1.0) : $0.1 > $1.1 }
            .map(\.0)
    }
}
