import Darwin
import Foundation

struct NowPlayingPayload: Equatable {
    var playing = false
    var title = ""
    var artist = ""
    var album = ""
    var app = ""
    var bundle = ""
    var artwork: String?

    static let empty = NowPlayingPayload()

    var hasTrack: Bool { !title.isEmpty || !artist.isEmpty }
    var artKey: String { "\(artist)\u{1e}\(album)\u{1e}\(title)" }
    var fingerprint: String { "\(playing)\u{1e}\(artKey)\u{1e}\(app)\u{1e}\(artwork ?? "")" }

    var js: [String: Any] {
        var dict: [String: Any] = [
            "playing": playing,
            "title": title,
            "artist": artist,
            "album": album,
            "app": app,
            "bundle": bundle,
        ]
        if let artwork { dict["artwork"] = artwork }
        return dict
    }

    static func parse(_ data: Data) -> NowPlayingPayload {
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
        else { return .empty }
        if let rows = obj["candidates"] as? [[String: Any]], !rows.isEmpty {
            return pick(rows.map(from))
        }
        return from(obj)
    }

    static func from(_ obj: [String: Any]) -> NowPlayingPayload {
        NowPlayingPayload(
            playing: boolish(obj["playing"]),
            title: stringish(obj["title"]),
            artist: stringish(obj["artist"]),
            album: stringish(obj["album"]),
            app: stringish(obj["app"]),
            bundle: stringish(obj["bundle"])
        )
    }

    static func pick(_ candidates: [NowPlayingPayload]) -> NowPlayingPayload {
        if let hit = candidates.first(where: { $0.playing && !isTransient($0.bundle) }) { return hit }
        if let hit = candidates.first(where: { $0.playing }) { return hit }
        if let hit = candidates.first(where: { $0.hasTrack && !isTransient($0.bundle) }) { return hit }
        return candidates.first ?? .empty
    }

    static func isTransient(_ bundle: String) -> Bool {
        let skip = [
            "com.apple.Safari",
            "com.apple.WebKit",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "net.whatsapp",
            "com.apple.MobileSMS",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "com.apple.mail",
        ]
        return skip.contains { bundle == $0 || bundle.hasPrefix($0 + ".") }
    }
}

enum ITunesArtwork {
    static func previewURL(from searchJSON: Data) -> URL? {
        guard let obj = try? JSONSerialization.jsonObject(with: searchJSON) as? [String: Any],
              let results = obj["results"] as? [[String: Any]],
              let first = results.first,
              let raw = (first["artworkUrl100"] as? String) ?? (first["artworkUrl60"] as? String)
        else { return nil }
        return URL(string: hires(raw))
    }

    static func hires(_ url: String) -> String {
        url.replacingOccurrences(of: #"\d+x\d+bb"#, with: "200x200bb", options: .regularExpression)
    }
}

enum MediaCommand: Int32 {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

final class NowPlaying: @unchecked Sendable {
    static let shared = NowPlaying()

    var onChange: (() -> Void)?

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macotron.media")
    private var current = NowPlayingPayload.empty
    private var lastArtKey = ""
    private var failedArtKey = ""
    private var artworkPath: String?
    private var busy = false
    private let client = MediaRemoteClient()

    func snapshot() -> NowPlayingPayload {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func send(_ command: MediaCommand) {
        _ = client.send(command)
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.poll() }
    }

    private func poll() {
        lock.lock()
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()
        defer {
            lock.lock()
            busy = false
            lock.unlock()
        }

        var payload = Self.readNowPlaying()
        lock.lock()
        let artKey = payload.artKey
        let artChanged = artKey != lastArtKey
        if artChanged {
            if let artworkPath {
                try? FileManager.default.removeItem(atPath: artworkPath)
            }
            artworkPath = nil
            lastArtKey = artKey
            failedArtKey = ""
        } else {
            payload.artwork = artworkPath
        }
        let skipArt = !payload.hasTrack || payload.artwork != nil || artKey == failedArtKey
        lock.unlock()

        if !skipArt {
            if let path = Self.fetchArtwork(payload) {
                payload.artwork = path
                lock.lock()
                artworkPath = path
                lock.unlock()
            } else {
                lock.lock()
                failedArtKey = artKey
                lock.unlock()
            }
        }
        apply(payload)
    }

    private func apply(_ payload: NowPlayingPayload) {
        lock.lock()
        let changed = payload != current
        current = payload
        let cb = onChange
        lock.unlock()
        if changed { cb?() }
    }

    private static let jxa = """
    function run() {
      function str(v) {
        if (v === undefined || v === null) return "";
        try {
          const u = ObjC.unwrap(v);
          if (u === undefined || u === null) return "";
          return String(u);
        } catch (e) {
          return "";
        }
      }
      function payload(info, client) {
        if (!info) return null;
        const rate = Number(str(info.valueForKey("kMRMediaRemoteNowPlayingInfoPlaybackRate"))) || 0;
        let app = "", bundle = "";
        try {
          app = str(client.displayName);
          bundle = str(client.bundleIdentifier);
        } catch (e) {}
        return {
          playing: rate > 0,
          title: str(info.valueForKey("kMRMediaRemoteNowPlayingInfoTitle")),
          artist: str(info.valueForKey("kMRMediaRemoteNowPlayingInfoArtist")),
          album: str(info.valueForKey("kMRMediaRemoteNowPlayingInfoAlbum")),
          app: app,
          bundle: bundle
        };
      }
      try {
        const MediaRemote = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/");
        MediaRemote.load;
        const Req = $.NSClassFromString("MRNowPlayingRequest");
        const candidates = [];
        try {
          const row = payload(Req.originNowPlayingItem.nowPlayingInfo, Req.originNowPlayingPlayerPath.client);
          if (row) candidates.push(row);
        } catch (e) {}
        try {
          const row = payload(Req.localNowPlayingItem.nowPlayingInfo, Req.localNowPlayingPlayerPath.client);
          if (row) candidates.push(row);
        } catch (e) {}
        return JSON.stringify(candidates.length ? { candidates: candidates } : { playing: false });
      } catch (e) {
        return JSON.stringify({ playing: false });
      }
    }
    """

    private static func readNowPlaying() -> NowPlayingPayload {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(jxa.utf8))
            stdin.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return .empty
        }
        return NowPlayingPayload.parse(stdout.fileHandleForReading.readDataToEndOfFile())
    }

    private static func fetchArtwork(_ payload: NowPlayingPayload) -> String? {
        let term = [payload.artist, payload.title].filter { !$0.isEmpty }.joined(separator: " ")
        guard !term.isEmpty, let search = searchURL(term: term, entity: "song") else { return nil }
        var cover = coverURL(from: search)
        if cover == nil, !payload.album.isEmpty,
           let albumSearch = searchURL(term: "\(payload.artist) \(payload.album)", entity: "album") {
            cover = coverURL(from: albumSearch)
        }
        guard let cover, let data = get(cover), !data.isEmpty else { return nil }
        let name = "macotron-nowplaying-\(stableHash(payload.artKey)).jpg"
        let path = FileManager.default.temporaryDirectory.appending(path: name)
        do {
            try data.write(to: path, options: .atomic)
            return path.path
        } catch {
            return nil
        }
    }

    private static func searchURL(term: String, entity: String) -> URL? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")
        comps?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "1"),
        ]
        return comps?.url
    }

    private static func coverURL(from search: URL) -> URL? {
        guard let data = get(search) else { return nil }
        return ITunesArtwork.previewURL(from: data)
    }

    private static func get(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return result
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

private final class MediaRemoteClient: @unchecked Sendable {
    private typealias SendFn = @convention(c) (Int32, UnsafeRawPointer?) -> DarwinBoolean
    private let sendFn: SendFn?

    init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        if let handle, let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendFn = unsafeBitCast(sym, to: SendFn.self)
        } else {
            sendFn = nil
        }
    }

    func send(_ command: MediaCommand) -> Bool {
        sendFn?(command.rawValue, nil).boolValue ?? false
    }
}

private func stringish(_ value: Any?) -> String {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

private func boolish(_ value: Any?) -> Bool {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    return false
}
