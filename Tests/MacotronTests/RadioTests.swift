import Foundation
import Testing
@testable import MacotronEngine

@MainActor
@Suite("Radio")
struct RadioTests {
    /// `http.get` answers with `body` for every URL; the player records what it
    /// was asked to play and reports `state` back.
    private func mock(body: String = "[]") -> String {
        """
        var store = {};
        var localStorage = {
            getItem: (k) => (k in store ? store[k] : null),
            setItem: (k, v) => { store[k] = String(v); },
            removeItem: (k) => { delete store[k]; }
        };
        var __query = null, __changed = null, statusConfig = null, played = [], posted = [];
        var state = { status: "stopped", url: null, title: null, streamTitle: null, position: 0, duration: null, volume: 1 };
        var macotron = {
            plugin: () => ({}),
            every: () => {},
            on: (name, fn) => { if (name === "player:changed") __changed = fn; },
            http: {
                get: () => Promise.resolve({ status: 200, body: \(String(reflecting: body)), headers: {} }),
                post: (url) => { posted.push(url); return Promise.resolve({ status: 200, body: "", headers: {} }); }
            },
            launcher: { query: (_id, fn) => { __query = fn; } },
            menubar: { status: (_id, cfg) => { statusConfig = cfg; } },
            player: {
                play: (url, opts) => { played.push({ url: url, opts: opts }); return true; },
                state: () => state,
                stop: () => {}, toggle: () => {}, seek: () => {}, setVolume: () => {}
            },
            command: () => {},
            panel: { open: () => "p", postMessage: () => {}, onMessage: () => {} },
            clipboard: { set: () => {} },
            notify: { toast: () => {} }
        };
        """
    }

    @Test("station rows come from radio-browser, without codecs AVPlayer cannot play")
    func stationRows() throws {
        let body = """
            [{"stationuuid":"u1","name":" Groove Salad ","url":"https://somafm.com/gs.pls","url_resolved":"https://ice.somafm.com/gs-128-mp3","codec":"MP3","bitrate":128,"countrycode":"US","tags":"ambient,chillout,lounge,sleep"},
             {"stationuuid":"u2","name":"Ogg Only","url_resolved":"https://x/ogg","codec":"OGG","bitrate":96,"countrycode":"DE","tags":""},
             {"stationuuid":"u3","name":"AAC Plus","url_resolved":"https://x/aac","codec":"AAC+","bitrate":0,"countrycode":"FR","tags":""}]
            """
        let engine = try PluginHarness.load(plugin: "radio.js", mock: mock(body: body))
        #expect(PluginHarness.run(engine, "__query('radiohead').length") == "0")
        PluginHarness.run(engine, "var rows = null; __query('radio groove').then((r) => { rows = r; })")
        let rows = PluginHarness.run(engine, "JSON.stringify(rows.map((r) => [r.title, r.subtitle]))")
        #expect(rows == #"[["Groove Salad","US · MP3 128 kbps · ambient, chillout, lounge"],["AAC Plus","FR · AAC+"]]"#)

        PluginHarness.run(engine, "rows[0].onClick()")
        #expect(PluginHarness.run(engine, "played[0].url") == "https://ice.somafm.com/gs-128-mp3")
        #expect(PluginHarness.run(engine, "posted[0]") == "https://all.api.radio-browser.info/json/url/u1")
        #expect(PluginHarness.run(engine, "JSON.parse(store['radio.recent'])[0].uuid") == "u1")
    }

    @Test("podcast RSS keeps CDATA as is and decodes entities")
    func parsesFeed() throws {
        let feed = """
            <rss><channel><title>Show</title>
            <item><title><![CDATA[Tips & <b>Tricks</b>]]></title><itunes:title>Not this</itunes:title>
              <enclosure length="1" type="audio/mpeg" url="https://x/a.mp3?a=1&amp;b=2"/></item>
            <item><title>Tom &amp; Jerry&#39;s &#x2019;</title><enclosure url='https://x/b.mp3' /></item>
            <item><title>No audio</title></item>
            </channel></rss>
            """
        let result = try PluginHarness.eval(plugin: "radio.js", mock: mock(), extra: """
            JSON.stringify(parseFeed(\(String(reflecting: feed))))
            """)
        #expect(result == #"[{"title":"Tips & <b>Tricks</b>","url":"https://x/a.mp3?a=1&b=2"},{"title":"Tom & Jerry's ’","url":"https://x/b.mp3"}]"#)
    }

    @Test("an episode resumes where it was paused, and restarts once finished")
    func resumesEpisode() throws {
        let feed = #"<item><title>Ep 1</title><enclosure url="https://x/1.mp3"/></item>"#
        let engine = try PluginHarness.load(plugin: "radio.js", mock: mock(body: feed))
        // `listen` is what Return on a podcast row runs: subscribe, fetch, play the newest.
        PluginHarness.run(engine, "listen({ name: 'Show', feed: 'https://x/feed' })")
        #expect(PluginHarness.run(engine, "JSON.parse(store['radio.subs'])[0].feed") == "https://x/feed")
        #expect(PluginHarness.run(engine, "played[0].opts.position") == "0")

        PluginHarness.run(engine, """
            state = { status: "paused", url: "https://x/1.mp3", title: "Ep 1", position: 125.6, duration: 1800, volume: 1 };
            __changed(state);
            """)
        #expect(PluginHarness.run(engine, "store['radio.pos.https://x/1.mp3']") == "125")
        PluginHarness.run(engine, "listen({ name: 'Show', feed: 'https://x/feed' })")
        #expect(PluginHarness.run(engine, "played[played.length - 1].opts.position") == "125")

        PluginHarness.run(engine, """
            state = { status: "paused", url: "https://x/1.mp3", title: "Ep 1", position: 1790, duration: 1800, volume: 1 };
            __changed(state);
            """)
        #expect(PluginHarness.run(engine, "'radio.pos.https://x/1.mp3' in store") == "false")
    }

    @Test("the menu bar title prefers the stream's song over the station")
    func titlePrefersStreamTitle() throws {
        let engine = try PluginHarness.load(plugin: "radio.js", mock: mock())
        #expect(PluginHarness.run(engine, "statusConfig.title") == "")
        PluginHarness.run(engine, """
            __changed({ status: "playing", url: "https://x/live", title: "Groove Salad", streamTitle: "Artist - Song", position: 3, duration: null, volume: 1 });
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title") == "Artist - Song")
        PluginHarness.run(engine, """
            __changed({ status: "playing", url: "https://x/live", title: "Groove Salad", streamTitle: null, position: 3, duration: null, volume: 1 });
            """)
        #expect(PluginHarness.run(engine, "statusConfig.title") == "Groove Salad")
    }
}
