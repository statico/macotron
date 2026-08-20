import Foundation
import Testing
@testable import Modules

@Suite("NowPlaying")
struct NowPlayingTests {
    @Test("parses JXA JSON and ignores noise")
    func parse() {
        let json = Data("""
        extra
        {"playing":true,"title":"Caravelle","artist":"Jazzanova","album":"Of All the Things","app":"SomaFM","bundle":"com.somafm.somafmmac"}
        """.utf8)
        let info = NowPlayingPayload.parse(json)
        #expect(info.playing)
        #expect(info.title == "Caravelle")
        #expect(info.artist == "Jazzanova")
        #expect(info.album == "Of All the Things")
        #expect(info.app == "SomaFM")
        #expect(info.bundle == "com.somafm.somafmmac")
        #expect(info.hasTrack)
    }

    @Test("empty JSON is idle")
    func empty() {
        let info = NowPlayingPayload.parse(Data("{}".utf8))
        #expect(!info.playing)
        #expect(!info.hasTrack)
        #expect(info.artwork == nil)
    }

    @Test("artwork URL is bumped to 200px")
    func hires() {
        let url = "https://is1-ssl.mzstatic.com/image/thumb/Music128/v4/x.jpg/100x100bb.jpg"
        #expect(ITunesArtwork.hires(url).hasSuffix("200x200bb.jpg"))
        let json = Data("""
        {"resultCount":1,"results":[{"artworkUrl100":"\(url)"}]}
        """.utf8)
        #expect(ITunesArtwork.previewURL(from: json)?.absoluteString.hasSuffix("200x200bb.jpg") == true)
    }

    @Test("prefers a playing music app over Safari and WhatsApp")
    func prefersMusicApp() {
        let safari = NowPlayingPayload.from([
            "playing": true, "title": "Tab", "app": "Safari", "bundle": "com.apple.Safari",
        ])
        let chat = NowPlayingPayload.from([
            "playing": true, "title": "Voice", "app": "WhatsApp", "bundle": "net.whatsapp.WhatsApp",
        ])
        let radio = NowPlayingPayload.from([
            "playing": true, "title": "Groove Salad", "app": "SomaFM", "bundle": "com.somafm.somafmmac",
        ])
        let picked = NowPlayingPayload.pick([safari, chat, radio])
        #expect(picked.bundle == "com.somafm.somafmmac")
        #expect(NowPlayingPayload.isTransient("com.apple.Safari"))
        #expect(NowPlayingPayload.isTransient("net.whatsapp.WhatsApp"))
        #expect(!NowPlayingPayload.isTransient("com.somafm.somafmmac"))
    }

    @Test("parses a candidates array")
    func candidates() {
        let json = Data("""
        {"candidates":[
          {"playing":true,"title":"Tab","app":"Safari","bundle":"com.apple.Safari"},
          {"playing":true,"title":"Groove Salad","artist":"SomaFM","app":"SomaFM","bundle":"com.somafm.somafmmac"}
        ]}
        """.utf8)
        let info = NowPlayingPayload.parse(json)
        #expect(info.bundle == "com.somafm.somafmmac")
        #expect(info.title == "Groove Salad")
    }
}
