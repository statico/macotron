import Darwin
import Foundation
import MacotronEngine

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

    var onChange: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onChange }
        set { lock.lock(); _onChange = newValue; lock.unlock() }
    }
    private var _onChange: (() -> Void)?

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "macotron.media")
    private var current = NowPlayingPayload.empty
    private var lastArtKey = ""
    private var failedArtKey = ""
    private var artworkPath: String?
    private var polledAt = Date.distantPast
    private var watching = false
    // Watcher state below is touched only on `queue`.
    private var wantWatch = false
    private var watcher: Process?
    private var watcherInput: Pipe?
    private var lineBuffer = Data()
    private var backoff: TimeInterval = 5
    private let client = MediaRemoteClient()

    func snapshot() -> NowPlayingPayload {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func send(_ command: MediaCommand) {
        _ = client.send(command)
        lock.lock()
        let watching = watching
        lock.unlock()
        // The watcher hears the change itself.
        guard !watching else { return }
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.poll() }
    }

    /// The snapshot, re-read first unless the watcher is keeping it current
    /// or a read landed in the last few seconds.
    func freshSnapshot() -> NowPlayingPayload {
        lock.lock()
        let stale = !watching && Date().timeIntervalSince(polledAt) > 5
        let known = current
        lock.unlock()
        guard stale else { return snapshot() }
        // Read here rather than on `queue`, which can be seconds deep in an
        // artwork download; the cover follows in media:changed.
        var payload = Self.readNowPlaying()
        if payload.artKey == known.artKey { payload.artwork = known.artwork }
        queue.async { [weak self, payload] in self?.ingest(payload) }
        return payload
    }

    /// Keep one long-lived osascript subscribed to MediaRemote's change
    /// notifications. Spawning osascript per read cost an exec and a
    /// malware-scan rule compile every time; this costs one process, asleep
    /// until a track or play state changes.
    func watch(_ on: Bool) {
        queue.async { [weak self] in
            // A repeat watch(true) would skip the restart backoff below.
            guard let self, on != wantWatch else { return }
            wantWatch = on
            if on { startWatcher() } else { stopWatcher() }
        }
    }

    private func startWatcher() {
        guard wantWatch, watcher == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.jxa, "watch"]
        // The script exits when this pipe closes, so it cannot outlive us.
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { [weak self] in self?.consume(chunk, from: process) }
        }
        let started = Date()
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { [weak self] in self?.watcherExited(process, after: Date().timeIntervalSince(started)) }
        }
        do {
            try process.run()
        } catch {
            watcherExited(nil, after: 0)
            return
        }
        watcher = process
        watcherInput = input
        lock.lock()
        watching = true
        lock.unlock()
    }

    private func stopWatcher() {
        let process = watcher
        watcher = nil
        watcherInput = nil
        lineBuffer.removeAll()
        lock.lock()
        watching = false
        lock.unlock()
        process?.terminate()
    }

    private func consume(_ chunk: Data, from process: Process) {
        guard process === watcher else { return }
        lineBuffer.append(chunk)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            ingest(NowPlayingPayload.parse(Data(line)))
        }
    }

    private func watcherExited(_ process: Process?, after lifetime: TimeInterval) {
        guard process == nil || process === watcher else { return }
        stopWatcher()
        guard wantWatch else { return }
        // Restart, but back off if it keeps dying so a broken script cannot
        // turn back into a spawn every few seconds.
        backoff = lifetime > 60 ? 5 : min(backoff * 2, 300)
        queue.asyncAfter(deadline: .now() + backoff) { [weak self] in self?.startWatcher() }
    }

    private func poll() {
        ingest(Self.readNowPlaying())
    }

    private func ingest(_ payload: NowPlayingPayload) {
        var payload = payload
        lock.lock()
        polledAt = Date()
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
        let cb = _onChange
        lock.unlock()
        if changed { cb?() }
    }

    /// With no arguments the script prints one reading and exits. With
    /// `watch` it prints a line per change until its stdin closes.
    static let jxa = """
    ObjC.import("stdlib");
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
    function read() {
      try {
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
    function watch() {
      ObjC.bindFunction("MRMediaRemoteRegisterForNowPlayingNotifications", ["void", ["id"]]);
      ObjC.bindFunction("dispatch_get_global_queue", ["id", ["long", "unsigned long"]]);
      $.MRMediaRemoteRegisterForNowPlayingNotifications($.dispatch_get_global_queue(0, 0));
      const out = $.NSFileHandle.fileHandleWithStandardOutput;
      let last = "";
      // Until MediaRemote proves it notifies this process, look every few
      // seconds, backing off while nothing changes; after that, only as a
      // safety net.
      let heard = false;
      let interval = 3;
      function emit() {
        const line = read();
        if (line === last) {
          interval = Math.min(interval * 2, 60);
          return;
        }
        interval = 3;
        last = line;
        out.writeData($(line + "\\n").dataUsingEncoding($.NSUTF8StringEncoding));
      }
      let pending = false;
      const center = $.NSNotificationCenter.defaultCenter;
      const main = $.NSOperationQueue.mainQueue;
      center.addObserverForNameObjectQueueUsingBlock($(), $(), main, function (note) {
        if (!/^kMRMediaRemote/.test(ObjC.unwrap(note.name))) return;
        heard = true;
        // One track change fires several notifications; read once for all.
        if (pending) return;
        pending = true;
        $.NSTimer.scheduledTimerWithTimeIntervalRepeatsBlock(0.3, false, function () {
          pending = false;
          emit();
        });
      });
      const stdin = $.NSFileHandle.fileHandleWithStandardInput;
      center.addObserverForNameObjectQueueUsingBlock(
        $.NSFileHandleReadToEndOfFileCompletionNotification, stdin, main, function () { $.exit(0); });
      stdin.readToEndOfFileInBackgroundAndNotify;
      emit();
      for (;;) {
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(heard ? 60 : interval));
        emit();
      }
    }
    function run(argv) {
      $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/").load;
      if (argv[0] === "watch") watch();
      return read();
    }
    """

    private static func readNowPlaying() -> NowPlayingPayload {
        let result = Subprocess.run("/usr/bin/osascript", ["-l", "JavaScript"], stdin: jxa)
        return NowPlayingPayload.parse(Data(result.stdout.utf8))
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
        let name = "macotron-nowplaying-\(PluginHash.sha256(source: payload.artKey)).jpg"
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
