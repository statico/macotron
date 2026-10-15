// APIs: player, http, launcher.query, menubar.status, localStorage, clipboard.set, notify.toast, every
macotron.plugin({
    title: "Radio & Podcasts",
    description: "Play internet radio and podcasts from the launcher, with the song in the menu bar.",
    help: "Open the launcher and type `radio` and a station name, or `podcast` and a show. Return plays it; a show is also subscribed, and starts at its newest episode. `radio` or `podcast` alone lists your favorite stations or subscribed shows. Podcasts resume where you stopped. The menu bar item has play and pause, volume, favorites, recent stations, and every subscribed show's latest episodes.",
});

const API = "https://all.api.radio-browser.info/json";
// radio-browser asks clients to name themselves.
const HEADERS = { headers: { "User-Agent": "Macotron" } };
// AVPlayer cannot decode Ogg, FLAC, or the video streams, so they never get a row.
const CODECS = ["MP3", "AAC", "AAC+"];

function load(key) {
    try {
        return JSON.parse(localStorage.getItem(key)) || [];
    } catch {
        return [];
    }
}

function save(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
}

let favs = load("radio.favs");
let recent = load("radio.recent");
let subs = load("radio.subs");
const episodes = {}; // feed url -> parsed episodes, newest first

function clip(s, n) {
    s = s || "";
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function json(res) {
    if (res.status !== 200) return null;
    try {
        return JSON.parse(res.body);
    } catch {
        return null;
    }
}

// ---- Radio ----

function stationRows(list) {
    return (list || [])
        .filter((s) => CODECS.includes(s.codec))
        .map((s) => {
            const station = { name: s.name.trim(), url: s.url_resolved || s.url, uuid: s.stationuuid };
            const format = s.bitrate ? `${s.codec} ${s.bitrate} kbps` : s.codec;
            const tags = (s.tags || "").split(",").filter(Boolean).slice(0, 3).join(", ");
            return stationRow(station, [s.countrycode || s.country, format, tags].filter(Boolean).join(" · "));
        });
}

function stationRow(station, subtitle) {
    return {
        id: station.url,
        title: station.name,
        subtitle: subtitle || "Favorite station",
        sfSymbol: "radio",
        onClick: () => playStation(station),
    };
}

async function searchStations(text) {
    const q = encodeURIComponent(text);
    const res = await macotron.http.get(
        `${API}/stations/search?name=${q}&hidebroken=true&order=votes&reverse=true&limit=20`,
        HEADERS
    );
    return stationRows(json(res));
}

function playStation(station) {
    savePosition(macotron.player.state());
    if (!macotron.player.play(station.url, { title: station.name })) {
        macotron.notify.toast("Radio", "Can't play " + station.name, { color: "error" });
        return;
    }
    recent = [station].concat(recent.filter((r) => r.url !== station.url)).slice(0, 5);
    save("radio.recent", recent);
    if (station.uuid) macotron.http.post(`${API}/url/${station.uuid}`, "", HEADERS);
}

// ---- Podcasts ----

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function decode(s) {
    s = String(s || "").trim();
    const cdata = s.match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
    if (cdata) return cdata[1].trim();
    return s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) =>
        e[0] !== "#" ? ENTITIES[e.toLowerCase()] || m
            : String.fromCodePoint(e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : Number(e.slice(1))));
}

// ponytail: regex, not an XML parser — podcast RSS is regular enough, and
// QuickJS has no DOMParser. Trusts the feed's order to be newest first.
function parseFeed(xml) {
    const items = String(xml || "").match(/<item[\s>][\s\S]*?<\/item>/g) || [];
    return items.map((item) => {
        const enclosure = item.match(/<enclosure\b[^>]*?\burl\s*=\s*["']([^"']+)["']/);
        const title = item.match(/<title(?:\s[^>]*)?>([\s\S]*?)<\/title>/);
        return enclosure && { title: decode(title && title[1]) || "Untitled", url: decode(enclosure[1]) };
    }).filter(Boolean);
}

async function refresh(show) {
    const res = await macotron.http.get(show.feed);
    if (res.status === 200) episodes[show.feed] = parseFeed(res.body);
    paint();
    return episodes[show.feed] || [];
}

function showRow(show) {
    return {
        id: show.feed,
        title: show.name,
        subtitle: show.author || "Podcast",
        sfSymbol: "mic",
        onClick: () => listen(show),
    };
}

async function searchShows(text) {
    const res = await macotron.http.get(
        `https://itunes.apple.com/search?media=podcast&term=${encodeURIComponent(text)}&limit=15`
    );
    const data = json(res);
    return ((data && data.results) || [])
        .filter((r) => r.feedUrl)
        .map((r) => showRow({ name: r.collectionName, author: r.artistName, feed: r.feedUrl, artwork: r.artworkUrl600 }));
}

async function listen(show) {
    if (!subs.some((s) => s.feed === show.feed)) {
        subs = subs.concat([show]);
        save("radio.subs", subs);
    }
    const list = await refresh(show);
    if (!list.length) return macotron.notify.toast(show.name, "No episodes found", { color: "error" });
    playEpisode(show, list[0]);
}

function playEpisode(show, episode) {
    savePosition(macotron.player.state());
    const position = Number(localStorage.getItem("radio.pos." + episode.url)) || 0;
    macotron.player.play(episode.url, { title: episode.title, artist: show.name, artwork: show.artwork, position });
}

// An episode within 30 s of its end is finished, so it starts over next time.
function savePosition(s) {
    if (!s.url || s.duration == null || (s.status !== "playing" && s.status !== "paused")) return;
    const key = "radio.pos." + s.url;
    if (s.duration - s.position <= 30) localStorage.removeItem(key);
    else localStorage.setItem(key, String(Math.floor(s.position)));
}

function unsubscribe(show) {
    subs = subs.filter((s) => s.feed !== show.feed);
    save("radio.subs", subs);
    delete episodes[show.feed];
    paint();
}

// ---- Menu bar ----

function stop() {
    savePosition(macotron.player.state());
    macotron.player.stop();
}

function skip(seconds) {
    const s = macotron.player.state();
    macotron.player.seek(Math.max(0, s.position + seconds));
}

function toggleFavorite(station) {
    favs = favs.some((f) => f.url === station.url)
        ? favs.filter((f) => f.url !== station.url)
        : favs.concat([station]);
    save("radio.favs", favs);
    paint();
}

function stationItems(list) {
    if (!list.length) return [{ title: "None", dimmed: true }];
    return list.map((st) => ({ title: st.name, onClick: () => playStation(st) }));
}

function showItems(show) {
    const list = episodes[show.feed];
    const rows = list
        ? list.slice(0, 10).map((ep) => ({ title: clip(ep.title, 60), onClick: () => playEpisode(show, ep) }))
        : [{ title: "Loading…", dimmed: true }];
    return rows.concat(["-", { title: "Unsubscribe", onClick: () => unsubscribe(show) }]);
}

function menu(s) {
    const rows = [];
    if (s.status === "stopped") {
        rows.push({ title: "Nothing playing", dimmed: true });
    } else {
        const live = s.duration == null;
        const station = live && recent.find((r) => r.url === s.url);
        rows.push({ title: s.title || s.url, dimmed: true });
        if (s.streamTitle) rows.push({ title: s.streamTitle, dimmed: true });
        if (s.error) rows.push({ title: s.error, dimmed: true });
        rows.push("-");
        rows.push({ title: s.status === "playing" ? "Pause" : "Play", onClick: () => macotron.player.toggle() });
        rows.push({ title: "Stop", onClick: stop });
        if (!live) {
            rows.push({ title: "Back 30 s", onClick: () => skip(-30) });
            rows.push({ title: "Forward 30 s", onClick: () => skip(30) });
        }
        rows.push({
            title: "Volume",
            menu: [25, 50, 75, 100].map((p) => ({
                title: p + "%",
                icon: Math.round(s.volume * 100) === p ? "checkmark" : undefined,
                onClick: () => { macotron.player.setVolume(p / 100); paint(); },
            })),
        });
        if (station) {
            const fav = favs.some((f) => f.url === station.url);
            rows.push({ title: fav ? "Remove Favorite" : "Add Favorite", onClick: () => toggleFavorite(station) });
        }
        if (s.streamTitle) {
            rows.push({
                title: "Copy Song",
                onClick: () => {
                    macotron.clipboard.set(s.streamTitle);
                    macotron.notify.toast("Copied", s.streamTitle, { color: "success" });
                },
            });
        }
    }
    rows.push("-");
    rows.push({ title: "Favorites", menu: stationItems(favs) });
    rows.push({ title: "Recent", menu: stationItems(recent) });
    rows.push({
        title: "Podcasts",
        menu: subs.length ? subs.map((show) => ({ title: show.name, menu: showItems(show) })) : [{ title: "None", dimmed: true }],
    });
    return rows;
}

function paint(s) {
    s = s || macotron.player.state();
    macotron.menubar.status("radio", {
        title: s.status === "stopped" ? "" : clip(s.streamTitle || s.title || "", 30),
        sfSymbol: "radio",
        menu: menu(s),
    });
}

macotron.on("player:changed", (s) => {
    savePosition(s);
    if (s.status === "error") macotron.notify.toast(s.title || "Radio", s.error || "Playback failed", { color: "error" });
    paint(s);
});

macotron.every(15_000, () => {
    const s = macotron.player.state();
    if (s.status === "playing") savePosition(s);
});

// ---- Launcher ----

macotron.launcher.query("radio", (query) => {
    // Only `radio …` and `podcast …` reach the network, so every other search stays local.
    const m = String(query || "").match(/^\s*(radio|podcast)(?:\s+(.*))?$/i);
    if (!m) return [];
    const text = (m[2] || "").trim();
    if (m[1].toLowerCase() === "radio") return text ? searchStations(text) : favs.map((st) => stationRow(st));
    return text ? searchShows(text) : subs.map(showRow);
});

paint();
subs.forEach(refresh);
macotron.every("1h", () => subs.forEach(refresh));
