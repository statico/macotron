import Foundation

enum URLRoute: Equatable {
    case match(String)
    case wildcard
    case fallback

    static func pick(_ rules: [(scheme: String, host: String)], url: URL) -> URLRoute {
        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        let relevant = rules.filter { $0.scheme.caseInsensitiveCompare(scheme) == .orderedSame }
        let named = relevant.filter { $0.host != "*" }

        if let exact = named.first(where: { $0.host.caseInsensitiveCompare(host) == .orderedSame }) {
            return .match(exact.host)
        }

        let suffixes = named.filter { host.lowercased().hasSuffix("." + $0.host.lowercased()) }
        if let best = suffixes.max(by: { $0.host.count < $1.host.count }) {
            return .match(best.host)
        }

        if relevant.contains(where: { $0.host == "*" }) {
            return .wildcard
        }
        return .fallback
    }
}
