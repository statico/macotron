// Player.swift — the AVPlayer behind macotron.player
import AppKit
import AVFoundation
import MediaPlayer

/// A snapshot of the player, as `macotron.player.state()` returns it.
struct PlayerState: Equatable {
    enum Status: String { case stopped, loading, playing, paused, error }

    var status = Status.stopped
    var url: String?
    var title: String?
    var artist: String?
    var streamTitle: String?
    var position: Double = 0
    var duration: Double?
    var volume: Double = 1
    var error: String?

    /// What `player:changed` compares. Position, volume and a VBR file's
    /// refined duration move without it; a duration appearing does not.
    var changeKey: PlayerState {
        var key = self
        key.position = 0
        key.volume = 0
        key.duration = duration == nil ? nil : 0
        return key
    }

    var js: [String: Any] {
        var dict: [String: Any] = [
            "status": status.rawValue,
            "url": orNull(url),
            "title": orNull(title),
            "artist": orNull(artist),
            "streamTitle": orNull(streamTitle),
            "position": position,
            "duration": orNull(duration),
            "volume": volume,
        ]
        if let error { dict["error"] = error }
        return dict
    }

    private func orNull(_ value: Any?) -> Any { value ?? NSNull() }
}

/// One AVPlayer for the whole app. It outlives plugin reloads, so a hot
/// reload does not cut the music; the module only swaps `onChange`.
@MainActor
final class Player: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = Player()

    /// Called when `state().changeKey` changes.
    var onChange: (@MainActor () -> Void)?

    private let player = AVPlayer()
    private var current = PlayerState()
    private var lastKey = PlayerState()
    private var pendingStart: Double?
    private var artwork: MPMediaItemArtwork?
    private var itemObservations: [NSKeyValueObservation] = []
    private var itemTokens: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var commandsInstalled = false

    override private init() {
        super.init()
        statusObservation = player.observe(\.timeControlStatus) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// `http`, `https` and `file` URLs only: anything else is refused.
    nonisolated static func playableURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme)
        else { return nil }
        return url
    }

    /// The ICY `StreamTitle` among a metadata group's items, as
    /// (identifier, string value) pairs. Stations that send nothing between
    /// songs send an empty title, which reads as none.
    nonisolated static func streamTitle(in items: [(identifier: String?, value: String?)]) -> String? {
        let raw = items.first { $0.identifier == AVMetadataIdentifier.icyMetadataStreamTitle.rawValue }?.value
        let title = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    func state() -> PlayerState {
        current.position = Self.seconds(player.currentTime()) ?? 0
        current.volume = Double(player.volume)
        return current
    }

    func play(_ url: URL, title: String?, artist: String?, artwork: String?, position: Double?) {
        detachItem()
        current = PlayerState(status: .loading, url: url.absoluteString, title: title, artist: artist)
        current.volume = Double(player.volume)
        pendingStart = position.flatMap { $0 > 0 ? $0 : nil }
        self.artwork = nil

        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        attach(item)
        player.replaceCurrentItem(with: item)
        player.play()
        installCommands()
        refresh()
        loadArtwork(artwork, for: url.absoluteString)
    }

    func pause() {
        player.pause()
        refresh()
    }

    func resume() {
        guard current.url != nil else { return }
        player.play()
        refresh()
    }

    func toggle() {
        if player.timeControlStatus == .paused { resume() } else { pause() }
    }

    func stop() {
        player.pause()
        detachItem()
        player.replaceCurrentItem(with: nil)
        current = PlayerState(volume: Double(player.volume))
        pendingStart = nil
        artwork = nil
        refresh()
    }

    /// Absolute. Live streams have no duration and ignore it.
    func seek(_ seconds: Double) {
        guard let duration = current.duration else { return }
        let target = min(max(seconds, 0), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateNowPlaying()
    }

    func setVolume(_ value: Double) {
        player.volume = Float(min(max(value, 0), 1))
    }

    // MARK: - Observing the item

    private func attach(_ item: AVPlayerItem) {
        itemObservations = [
            item.observe(\.status) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
            item.observe(\.duration) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            },
        ]
        let center = NotificationCenter.default
        itemTokens = [
            // A dropped stream ends here rather than in the item's status.
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) {
                @Sendable [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let message = error?.localizedDescription ?? "Playback stopped"
                MainActor.assumeIsolated { self?.fail(message) }
            },
        ]
        // A file that plays to its end just pauses there, keeping its url, so a
        // plugin can tell the episode finished.
    }

    private func detachItem() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemTokens = []
    }

    private func fail(_ message: String) {
        guard current.url != nil else { return }
        current.error = message
        player.pause()
        refresh()
    }

    /// Re-derives the status from AVPlayer, updates Now Playing, and tells
    /// the module when something a listener cares about moved.
    private func refresh() {
        if let item = player.currentItem, current.url != nil {
            if item.status == .failed, current.error == nil {
                current.error = item.error?.localizedDescription ?? "Could not play"
                player.pause()
            }
            current.duration = Self.seconds(item.duration)
            if item.status == .readyToPlay, let start = pendingStart {
                pendingStart = nil
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
            }
        }
        current.status = Self.status(
            hasItem: current.url != nil,
            failed: current.error != nil,
            control: player.timeControlStatus
        )
        updateNowPlaying()
        let key = state().changeKey
        guard key != lastKey else { return }
        lastKey = key
        onChange?()
    }

    private static func status(hasItem: Bool, failed: Bool, control: AVPlayer.TimeControlStatus) -> PlayerState.Status {
        guard hasItem else { return .stopped }
        if failed { return .error }
        switch control {
        case .playing: return .playing
        case .waitingToPlayAtSpecifiedRate: return .loading
        default: return .paused
        }
    }

    /// Seconds, or nil for an indefinite (live) or not-yet-known time.
    private static func seconds(_ time: CMTime) -> Double? {
        time.isNumeric ? time.seconds : nil
    }

    // MARK: - ICY metadata

    // The delegate queue is main, so this runs there; the items are not
    // Sendable, so the strings come out before hopping onto the actor.
    // `value(forKey:)` reads the already-delivered value without the
    // Swift-deprecated `stringValue` or an async load per song change.
    nonisolated func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let pairs = groups.flatMap(\.items).map {
            (identifier: $0.identifier?.rawValue, value: $0.value(forKey: "stringValue") as? String)
        }
        guard let title = Self.streamTitle(in: pairs) else { return }
        MainActor.assumeIsolated {
            guard current.url != nil, current.streamTitle != title else { return }
            current.streamTitle = title
            refresh()
        }
    }

    // MARK: - Now Playing and remote commands

    private func updateNowPlaying() {
        // Leave Now Playing alone until Macotron has played something.
        guard commandsInstalled else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard current.url != nil else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        // A radio song reads as the title, with the station as its artist.
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.streamTitle ?? current.title ?? current.url ?? "",
            MPNowPlayingInfoPropertyIsLiveStream: current.duration == nil,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Self.seconds(player.currentTime()) ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: Double(player.rate),
        ]
        if let artist = current.streamTitle != nil ? current.title : current.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let duration = current.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = current.status == .playing || current.status == .loading ? .playing : .paused

        let commands = MPRemoteCommandCenter.shared()
        commands.skipForwardCommand.isEnabled = current.duration != nil
        commands.skipBackwardCommand.isEnabled = current.duration != nil
    }

    /// Once, on first play, so Macotron only claims media keys after it has
    /// played something.
    private func installCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let commands = MPRemoteCommandCenter.shared()
        Self.handle(commands.playCommand) { $0.resume() }
        Self.handle(commands.pauseCommand) { $0.pause() }
        Self.handle(commands.togglePlayPauseCommand) { $0.toggle() }
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.preferredIntervals = [30]
        Self.handle(commands.skipForwardCommand) { $0.seek($0.state().position + 30) }
        Self.handle(commands.skipBackwardCommand) { $0.seek($0.state().position - 30) }
    }

    // Built outside the actor so the handler is not inferred main-isolated:
    // MediaPlayer may call it off the main thread.
    private nonisolated static func handle(
        _ command: MPRemoteCommand, _ action: @escaping @MainActor @Sendable (Player) -> Void
    ) {
        command.addTarget { _ in
            Task { @MainActor in action(Player.shared) }
            return .success
        }
    }

    private func loadArtwork(_ raw: String?, for url: String) {
        guard let raw, let source = raw.hasPrefix("/") ? Optional(URL(fileURLWithPath: raw)) : Self.playableURL(raw) else { return }
        Task {
            guard let data = try? await URLSession.shared.data(from: source).0,
                  current.url == url,
                  let artwork = Self.artwork(data)
            else { return }
            self.artwork = artwork
            updateNowPlaying()
        }
    }

    // Nonisolated for the same reason as `handle`: MediaPlayer asks for the
    // image on its own queue.
    private nonisolated static func artwork(_ data: Data) -> MPMediaItemArtwork? {
        guard let size = NSImage(data: data)?.size else { return nil }
        return MPMediaItemArtwork(boundsSize: size) { _ in NSImage(data: data) ?? NSImage() }
    }
}
