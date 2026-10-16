// APIs: player, http, launcher.query, menubar.status, localStorage, clipboard.set, notify.toast, every
const opts = macotron.plugin({
    title: "Radio & Podcasts",
    description: "Play internet radio and podcasts from the launcher, with the song in the menu bar.",
    help: "Open the launcher and type `radio` and a station name, or `podcast` and a show. Return plays it; a show is also subscribed, and starts at its newest episode. `radio` alone offers the station browser (search, genres, countries, and a star to favorite) and lists your favorites; `podcast` alone lists your subscribed shows. Podcasts resume where you stopped. The menu bar item has play and pause, volume, favorites, recent stations, and every subscribed show's latest episodes.",
    options: {
        showTitle: {
            type: "boolean",
            label: "Show song or station in the menu bar",
            help: "Off leaves only the radio icon.",
            default: true,
        },
    },
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

function toStations(list) {
    return (list || [])
        .filter((s) => CODECS.includes(s.codec))
        .map((s) => {
            const format = s.bitrate ? `${s.codec} ${s.bitrate} kbps` : s.codec;
            const tags = (s.tags || "").split(",").filter(Boolean).slice(0, 3).join(", ");
            return {
                name: s.name.trim(),
                url: s.url_resolved || s.url,
                uuid: s.stationuuid,
                subtitle: [s.countrycode || s.country, format, tags].filter(Boolean).join(" · "),
            };
        });
}

function stationRow(station) {
    return {
        id: station.url,
        title: station.name,
        subtitle: station.subtitle || "Favorite station",
        sfSymbol: "radio",
        onClick: () => playStation(station),
    };
}

// `filter` is a radio-browser search parameter: `name=…`, `tag=…`, or `countrycode=…`.
async function fetchStations(filter, limit) {
    const res = await macotron.http.get(
        `${API}/stations/search?${filter}&hidebroken=true&order=votes&reverse=true&limit=${limit}`,
        HEADERS
    );
    return toStations(json(res));
}

async function searchStations(text) {
    return (await fetchStations("name=" + encodeURIComponent(text), 20)).map(stationRow);
}

function playStation(station) {
    savePosition(macotron.player.state());
    if (!macotron.player.play(station.url, { title: station.name })) {
        macotron.notify.toast("Radio", "Can't play " + station.name, { color: "error" });
        return;
    }
    recent = [station].concat(recent.filter((r) => r.url !== station.url)).slice(0, 5);
    syncBrowser();
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
    syncBrowser();
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
    rows.push({ title: "Browse Stations…", onClick: openBrowser });
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
        title: s.status === "stopped" || opts.showTitle === false ? "" : clip(s.streamTitle || s.title || "", 30),
        sfSymbol: "radio",
        menu: menu(s),
    });
}

macotron.on("player:changed", (s) => {
    savePosition(s);
    if (s.status === "error") macotron.notify.toast(s.title || "Radio", s.error || "Playback failed", { color: "error" });
    paint(s);
    syncBrowser();
});

// ---- Station browser panel ----

const BROWSER_HTML = `<style>
#q { width:100%; font-size:18px; padding:6px 2px; border:0; background:transparent; color:var(--macotron-label); outline:none; }
#tabs { display:flex; gap:4px; }
#tabs button { flex:1; }
#tabs button.on { background:var(--macotron-accent); color:var(--macotron-accent-text); }
#chips { display:flex; flex-wrap:wrap; gap:6px; }
#chips:empty { display:none; }
.chip { padding:3px 10px; border-radius:12px; cursor:pointer; background:var(--macotron-fill); }
.chip.on { background:var(--macotron-accent); color:var(--macotron-accent-text); }
.row { display:flex; align-items:center; gap:10px; padding:6px 8px; border-radius:8px; cursor:pointer; }
.row:hover { background:var(--macotron-fill); }
.row.playing { background:var(--macotron-selected); color:var(--macotron-selected-text); }
.row .text { flex:1; min-width:0; }
.row .name, .row .sub { white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.row .sub { font-size:11px; color:var(--macotron-secondary-label); }
.row.playing .sub { color:inherit; opacity:0.8; }
.icon { width:22px; text-align:center; font-size:15px; }
.star { cursor:pointer; color:var(--macotron-secondary-label); }
.star.on { color:#f5b400; }
</style>
<input id="q" autofocus placeholder="Search Stations…" spellcheck="false" aria-label="Search stations">
<div id="tabs" role="tablist">
  <button data-tab="favorites">Favorites</button><button data-tab="top">Top</button>
  <button data-tab="genres">Genres</button><button data-tab="countries">Countries</button>
</div>
<div id="chips"></div>
<div id="list" class="grow scroll"></div>
<script>
const send = (d) => webkit.messageHandlers.macotron.postMessage(d);
let stations = [], favs = [], playing = null, seq = 0, timer = null;
const $ = (id) => document.getElementById(id);
function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;" }[c])); }
function ask(d) { d.seq = ++seq; $("list").innerHTML = "<p class='muted'>Loading…</p>"; send(d); }
function tab(name) {
  document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("on", b.dataset.tab === name));
  $("chips").innerHTML = "";
  $("q").value = "";
  ask({ tab: name });
}
function paint() {
  $("list").innerHTML = stations.length ? stations.map((s, i) =>
    "<div class='row" + (s.url === playing ? " playing" : "") + "' data-i='" + i + "'>" +
    "<span class='icon'>" + (s.url === playing ? "■" : "▶") + "</span>" +
    "<div class='text'><div class='name'>" + esc(s.name) + "</div><div class='sub'>" + esc(s.subtitle) + "</div></div>" +
    "<span class='icon star" + (favs.includes(s.url) ? " on" : "") + "' title='Favorite'>" + (favs.includes(s.url) ? "★" : "☆") + "</span></div>"
  ).join("") : "<p class='muted'>No stations</p>";
}
window.__macotronReceive = (d) => {
  if (!d) return;
  if (d.favs) favs = d.favs;
  if ("playing" in d) playing = d.playing;
  if (d.chips && d.seq === seq) {
    $("chips").innerHTML = d.chips.map((c) =>
      "<span class='chip' data-kind='" + c.kind + "' data-value='" + esc(c.value) + "'>" + esc(c.label) + "</span>").join("");
    $("list").innerHTML = "";
    return;
  }
  if (d.stations && d.seq === seq) stations = d.stations;
  paint();
};
$("q").oninput = (e) => {
  clearTimeout(timer);
  const text = e.target.value.trim();
  timer = setTimeout(() => text ? ask({ search: text }) : tab("favorites"), 300);
};
$("tabs").onclick = (e) => { if (e.target.dataset.tab) tab(e.target.dataset.tab); };
$("chips").onclick = (e) => {
  const c = e.target.closest(".chip");
  if (!c) return;
  document.querySelectorAll(".chip").forEach((x) => x.classList.toggle("on", x === c));
  ask({ [c.dataset.kind]: c.dataset.value });
};
$("list").onclick = (e) => {
  const row = e.target.closest(".row");
  if (!row) return;
  const s = stations[+row.dataset.i];
  send(e.target.closest(".star") ? { fav: s } : s.url === playing ? { stop: true } : { play: s });
};
tab("favorites");
</script>`;

let browserId = null;

function syncBrowser() {
    if (!browserId) return;
    const s = macotron.player.state();
    macotron.panel.postMessage(browserId, {
        favs: favs.map((f) => f.url),
        playing: s.status === "stopped" ? null : s.url,
    });
}

async function chips(kind) {
    const res = await macotron.http.get(
        `${API}/${kind === "tag" ? "tags" : "countries"}?order=stationcount&reverse=true&hidebroken=true&limit=60`,
        HEADERS
    );
    return (json(res) || []).map((c) => kind === "tag"
        ? { kind, label: c.name, value: c.name }
        : { kind, label: c.name, value: c.iso_3166_1 });
}

async function answer(id, d) {
    const reply = { seq: d.seq };
    if (d.tab === "favorites") reply.stations = favs;
    else if (d.tab === "top") reply.stations = await fetchStations("", 60);
    else if (d.tab === "genres") reply.chips = await chips("tag");
    else if (d.tab === "countries") reply.chips = await chips("country");
    else if (d.search) reply.stations = await fetchStations("name=" + encodeURIComponent(d.search), 60);
    else if (d.tag) reply.stations = await fetchStations("tagExact=true&tag=" + encodeURIComponent(d.tag), 60);
    else if (d.country) reply.stations = await fetchStations("countrycode=" + encodeURIComponent(d.country), 60);
    if (browserId === id) macotron.panel.postMessage(id, reply);
}

function openBrowser() {
    const id = macotron.panel.open({ id: "radio-browser", title: "Radio Stations", width: 460, height: 600, html: BROWSER_HTML });
    browserId = id;
    syncBrowser();
    macotron.panel.onMessage(id, (d) => {
        if (!d) return;
        if (d.play) playStation(d.play);
        else if (d.stop) stop();
        else if (d.fav) toggleFavorite(d.fav);
        else answer(id, d);
    });
}

macotron.on("panel:closed", ({ id }) => {
    if (id === browserId) browserId = null;
});

macotron.command("Browse Radio Stations", "Search and browse internet radio, and pick favorites", openBrowser);

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
    if (m[1].toLowerCase() === "radio") {
        if (text) return searchStations(text);
        const browse = { id: "radio-browse", title: "Browse Radio Stations…", subtitle: "Search, genres, countries, favorites", sfSymbol: "radio", onClick: openBrowser };
        return [browse].concat(favs.map(stationRow));
    }
    return text ? searchShows(text) : subs.map(showRow);
});

paint();
subs.forEach(refresh);
macotron.every("1h", () => subs.forEach(refresh));
