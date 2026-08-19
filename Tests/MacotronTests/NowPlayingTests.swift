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
}
