// CommunityCatalog.swift — Community plugins, found through a GitHub topic.
//
// There is no index file and no server. Authors add the `macotron-plugin`
// topic to their repository and the app finds it. One plugin per repository,
// one `.js` file at the root, because the search result already carries the
// name, the description, the star count, and the default branch: listing the
// repository would cost a second API call against a 60-per-hour budget.
//
// Downloads come off raw.githubusercontent.com, which is a CDN and does not
// spend the API quota. Nothing here is trusted: the bytes go through the same
// scan-and-approve sheet as a plugin that changed on disk.
import Foundation

/// Where a downloaded plugin came from. Bundled catalog plugins leave it nil.
public struct CommunityOrigin: Equatable, Sendable {
    /// "owner/repo"
    public var repo: String
    public var stars: Int
    public var pushedAt: Date?
    public var homepage: URL
    public var sourceURL: URL

    public init(repo: String, stars: Int, pushedAt: Date? = nil, homepage: URL, sourceURL: URL) {
        self.repo = repo
        self.stars = stars
        self.pushedAt = pushedAt
        self.homepage = homepage
        self.sourceURL = sourceURL
    }

    public var owner: String { String(repo.prefix { $0 != "/" }) }
}

public struct CommunityEntry: Equatable, Sendable, Identifiable {
    public var repo: String
    public var title: String
    public var summary: String
    public var stars: Int
    public var pushedAt: Date?
    public var defaultBranch: String
    public var homepage: URL

    public init(
        repo: String,
        title: String,
        summary: String,
        stars: Int,
        pushedAt: Date?,
        defaultBranch: String,
        homepage: URL
    ) {
        self.repo = repo
        self.title = title
        self.summary = summary
        self.stars = stars
        self.pushedAt = pushedAt
        self.defaultBranch = defaultBranch
        self.homepage = homepage
    }

    public var id: String { repo }
    public var owner: String { String(repo.prefix { $0 != "/" }) }
    public var repoName: String { String(repo.split(separator: "/").last ?? "") }

    /// What the plugin is called once it lands in the workdir. Derived, never
    /// stored, so the update check can match an installed file back to its
    /// repository without the app keeping a side table.
    public var filename: String { CommunityCatalog.filename(forRepo: repoName) }
}

public enum CommunityCatalogError: LocalizedError, Equatable {
    case rateLimited
    case http(Int)
    case noPluginFile(repo: String, tried: [String])
    case tooLarge(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "GitHub is rate limiting this Mac. Try again in a minute."
        case .http(let code):
            return "GitHub answered with HTTP \(code)."
        case .noPluginFile(let repo, let tried):
            return "\(repo) has no plugin file. Looked for \(tried.joined(separator: ", "))."
        case .tooLarge(let name):
            return "\(name) is larger than 512 KB."
        case .malformed:
            return "GitHub sent an answer Macotron could not read."
        }
    }
}

public enum CommunityCatalog {
    public static let topic = "macotron-plugin"
    public static let topicURL = URL(string: "https://github.com/topics/macotron-plugin")!

    /// Plugins are text. Anything this big is not a plugin.
    static let maxSourceBytes = 512 * 1024

    // MARK: - Naming

    /// `macotron-weather` installs as `weather.js`. Two repositories can still
    /// collide here; that lands in the existing overwrite warning.
    public static func filename(forRepo name: String) -> String {
        var base = name.lowercased()
        for prefix in ["macotron-", "macotron."] where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
        }
        for suffix in ["-plugin", ".plugin", "-macotron", ".js"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let allowed = base.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        base = String(allowed).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return (base.isEmpty ? name.lowercased() : base) + ".js"
    }

    /// Filenames to try in the repository, in order. The repository name comes
    /// first so a well-named repo costs one request.
    static func candidates(for entry: CommunityEntry) -> [String] {
        var names = ["\(entry.repoName).js", entry.filename, "plugin.js", "index.js"]
        var seen = Set<String>()
        names = names.filter { seen.insert($0).inserted }
        return names
    }

    static func rawURL(repo: String, branch: String, path: String) -> URL? {
        URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/\(path)")
    }

    // MARK: - Search

    /// One search API call. Unauthenticated search allows 10 calls per minute
    /// for each IP address, and every user has their own, so a person who
    /// browses never reaches the limit.
    public static func search(session: URLSession = .shared) async throws -> [CommunityEntry] {
        var comps = URLComponents(string: "https://api.github.com/search/repositories")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "topic:\(topic) fork:false"),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        guard let url = comps.url else { throw CommunityCatalogError.malformed }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Macotron", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)
        try check(response)
        return parse(searchPayload: data)
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CommunityCatalogError.malformed }
        switch http.statusCode {
        case 200..<300: return
        case 403, 429: throw CommunityCatalogError.rateLimited
        default: throw CommunityCatalogError.http(http.statusCode)
        }
    }

    static func parse(searchPayload data: Data) -> [CommunityEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            return []
        }
        let dates = ISO8601DateFormatter()
        return items.compactMap { item in
            guard let repo = item["full_name"] as? String,
                  repo.contains("/"),
                  item["archived"] as? Bool != true,
                  let branch = item["default_branch"] as? String,
                  let page = (item["html_url"] as? String).flatMap(URL.init(string:)) else {
                return nil
            }
            let name = (item["name"] as? String) ?? repo
            return CommunityEntry(
                repo: repo,
                title: displayTitle(repoName: name),
                summary: (item["description"] as? String) ?? "",
                stars: (item["stargazers_count"] as? Int) ?? 0,
                pushedAt: (item["pushed_at"] as? String).flatMap(dates.date(from:)),
                defaultBranch: branch,
                homepage: page
            )
        }
    }

    /// `macotron-window-grid` reads as "Window Grid" in the list. The plugin's
    /// own `title` wins once the source is downloaded.
    static func displayTitle(repoName: String) -> String {
        let stem = String(filename(forRepo: repoName).dropLast(3))
        let words = stem.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard !words.isEmpty else { return repoName }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Download

    /// Downloads the plugin source off the CDN. This spends no API quota, so
    /// probing a few filenames is cheaper than listing the repository.
    public static func fetchSource(
        _ entry: CommunityEntry,
        session: URLSession = .shared
    ) async throws -> (source: String, url: URL) {
        let tried = candidates(for: entry)
        var lastError: Error?
        for path in tried {
            guard let url = rawURL(repo: entry.repo, branch: entry.defaultBranch, path: path) else {
                continue
            }
            var request = URLRequest(url: url)
            request.setValue("Macotron", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            request.cachePolicy = .reloadRevalidatingCacheData
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard http.statusCode == 200 else { continue }
                guard data.count <= maxSourceBytes else {
                    throw CommunityCatalogError.tooLarge(path)
                }
                guard let source = String(data: data, encoding: .utf8) else { continue }
                return (source, url)
            } catch let error as CommunityCatalogError {
                throw error
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw CommunityCatalogError.noPluginFile(repo: entry.repo, tried: tried)
    }
}
