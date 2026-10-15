import Foundation
import Testing
@testable import Modules

@Suite("Player")
struct PlayerTests {
    @Test("only http, https and file URLs play")
    func schemes() {
        #expect(Player.playableURL("https://ice1.somafm.com/groovesalad-128-mp3") != nil)
        #expect(Player.playableURL("HTTP://example.com/stream") != nil)
        #expect(Player.playableURL("file:///tmp/episode.mp3") != nil)
        #expect(Player.playableURL("javascript:alert(1)") == nil)
        #expect(Player.playableURL("ftp://example.com/a.mp3") == nil)
        #expect(Player.playableURL("/tmp/episode.mp3") == nil)
        #expect(Player.playableURL("") == nil)
    }

    @Test("StreamTitle is picked out of the ICY items and trimmed")
    func streamTitle() {
        let items: [(identifier: String?, value: String?)] = [
            (identifier: "icy/StreamUrl", value: "https://somafm.com"),
            (identifier: "icy/StreamTitle", value: "  Bonobo - Kerala \n"),
        ]
        #expect(Player.streamTitle(in: items) == "Bonobo - Kerala")
        #expect(Player.streamTitle(in: [(identifier: "icy/StreamTitle", value: "  ")]) == nil)
        #expect(Player.streamTitle(in: [(identifier: "icy/StreamUrl", value: "x")]) == nil)
        #expect(Player.streamTitle(in: []) == nil)
    }

    @Test("state reaches JS with nulls for what is unknown")
    func stateJS() {
        let stopped = PlayerState().js
        #expect(stopped["status"] as? String == "stopped")
        #expect(stopped["url"] is NSNull)
        #expect(stopped["duration"] is NSNull)
        #expect(stopped["error"] == nil)

        let failed = PlayerState(status: .error, url: "https://x", duration: 60, error: "Gone").js
        #expect(failed["duration"] as? Double == 60)
        #expect(failed["error"] as? String == "Gone")
    }

    @Test("position and volume do not count as a change; a duration appearing does")
    func changeKey() {
        let base = PlayerState(status: .playing, url: "https://x", position: 1, volume: 1)
        var moved = base
        moved.position = 30
        moved.volume = 0.5
        #expect(moved.changeKey == base.changeKey)

        var refined = base
        refined.duration = 100
        var later = refined
        later.duration = 101
        #expect(refined.changeKey != base.changeKey)
        #expect(later.changeKey == refined.changeKey)

        var song = base
        song.streamTitle = "A - B"
        #expect(song.changeKey != base.changeKey)
    }
}
