// APIs: shell.run, localStorage, panel, launcher.query, clipboard.set, event.post
const opts = macotron.plugin({
  title: "Emoji Picker",
  description: "Search emoji by name, keep the ones you use most at the top, and insert one.",
  options: {
    size: {
      type: "dropdown",
      label: "Emoji size",
      default: "l",
      choices: [
        { value: "s", label: "Small" },
        { value: "m", label: "Medium" },
        { value: "l", label: "Large" },
      ],
    },
  },
});

// Columns are derived from the cell size so the grid keeps filling the panel.
const SIZES = { s: { px: 18, cols: 14 }, m: { px: 30, cols: 8 }, l: { px: 40, cols: 6 } };
const SIZE = SIZES[opts.size] || SIZES.l;

// macOS ships every emoji and its name here, so no list is bundled with the plugin.
const NAMES_PLIST =
  "/System/Library/PrivateFrameworks/CoreEmoji.framework/Versions/A/Resources/en.lproj/AppleName.strings";

// ponytail: codepoint ranges, not the real Unicode group table — a handful of
// emoji land one section off. Parse emojimeta.dat if that ever matters.
const RANGES = [
  [0x1f1e6, 0x1f1ff, "Flags"],
  [0x1f3f3, 0x1f3f5, "Flags"],
  [0x1f600, 0x1f64f, "Smileys & People"],
  [0x1f464, 0x1f487, "Smileys & People"],
  [0x1f440, 0x1f450, "Smileys & People"],
  [0x1f90c, 0x1f93a, "Smileys & People"],
  [0x1f970, 0x1f97a, "Smileys & People"],
  [0x1f9d0, 0x1f9df, "Smileys & People"],
  [0x1f300, 0x1f344, "Animals & Nature"],
  [0x1f400, 0x1f43f, "Animals & Nature"],
  [0x1f980, 0x1f9ae, "Animals & Nature"],
  [0x1f345, 0x1f37f, "Food & Drink"],
  [0x1f950, 0x1f96f, "Food & Drink"],
  [0x1f9c0, 0x1f9cf, "Food & Drink"],
  [0x1f380, 0x1f3cf, "Activity"],
  [0x1f3d0, 0x1f3d3, "Activity"],
  [0x1f93b, 0x1f94f, "Activity"],
  [0x1f3d4, 0x1f3ff, "Travel & Places"],
  [0x1f5fa, 0x1f5ff, "Travel & Places"],
  [0x1f680, 0x1f6ff, "Travel & Places"],
  [0x1f4a0, 0x1f5f9, "Objects"],
  [0x1f9f0, 0x1faff, "Objects"],
];
const ORDER = [
  "Smileys & People",
  "Animals & Nature",
  "Food & Drink",
  "Activity",
  "Travel & Places",
  "Objects",
  "Symbols",
  "Flags",
];

function categoryOf(emoji) {
  const cp = emoji.codePointAt(0);
  for (const [lo, hi, name] of RANGES) if (cp >= lo && cp <= hi) return name;
  return "Symbols";
}

let emoji = [];

async function load() {
  const cached = localStorage.getItem("emoji:list:v1");
  if (cached) {
    emoji = JSON.parse(cached);
    return;
  }
  const out = await macotron.shell.run("/usr/bin/plutil", ["-convert", "json", "-o", "-", NAMES_PLIST]);
  const names = JSON.parse(out.stdout);
  emoji = Object.keys(names)
    .map((e) => ({ e, n: names[e], c: categoryOf(e) }))
    .sort((a, b) => ORDER.indexOf(a.c) - ORDER.indexOf(b.c) || a.e.codePointAt(0) - b.e.codePointAt(0));
  localStorage.setItem("emoji:list:v1", JSON.stringify(emoji));
}

function recent() {
  return JSON.parse(localStorage.getItem("emoji:recent") || "[]");
}

function pick(e) {
  const mru = [e].concat(recent().filter((x) => x !== e)).slice(0, 16);
  localStorage.setItem("emoji:recent", JSON.stringify(mru));
  macotron.clipboard.set(e);
  // Give focus time to fall back to the app the picker covered.
  setTimeout(() => macotron.event.post({ type: "unicode", string: e }), 150);
}

function search(q, limit) {
  q = q.toLowerCase().trim();
  if (!q) return [];
  const hits = [];
  for (const it of emoji) {
    const n = it.n;
    const at = n.indexOf(q);
    if (at < 0) continue;
    hits.push({ it, rank: at === 0 ? 0 : n[at - 1] === " " ? 1 : 2 });
    if (hits.length > 400) break;
  }
  hits.sort((a, b) => a.rank - b.rank);
  return hits.slice(0, limit).map((h) => h.it);
}

// Sections the panel paints: recents first, then the categories.
function sections() {
  const mru = recent()
    .map((e) => emoji.find((it) => it.e === e))
    .filter(Boolean);
  const out = mru.length ? [{ title: "Recent", items: mru }] : [];
  for (const name of ORDER) {
    const items = emoji.filter((it) => it.c === name);
    if (items.length) out.push({ title: name, items });
  }
  return out;
}

const PANEL_HTML = `<style>
:root { --cols: ${SIZE.cols}; --cell: ${SIZE.px}px; }
#q { width:100%; font-size:20px; padding:8px 4px; border:0; background:transparent; color:var(--macotron-label); outline:none; }
#head { border-bottom:1px solid light-dark(rgba(0,0,0,0.08), rgba(255,255,255,0.08)); padding-bottom:10px; margin-bottom:14px; }
h3 { font-size:12px; text-transform:none; color:var(--macotron-secondary-label); margin:12px 0 6px; font-weight:600; }
h3 span { margin-left:8px; opacity:0.6; font-weight:400; }
#body { padding:2px; }
.grid { display:grid; grid-template-columns:repeat(var(--cols), 1fr); gap:6px; }
.cell { font-size:var(--cell); line-height:1; aspect-ratio:1; display:flex; align-items:center; justify-content:center;
  border-radius:10px; cursor:pointer; background:light-dark(rgba(0,0,0,0.04), rgba(255,255,255,0.06)); }
.cell.on { outline:2px solid var(--macotron-accent); outline-offset:-1px; background:var(--macotron-selected); }
</style>
<div id="head"><input id="q" autofocus placeholder="Search Emoji…" spellcheck="false"></div>
<div id="body" class="grow scroll"></div>
<script>
let sections = [], flat = [], sel = 0;
const COLS = ${SIZE.cols};
function esc(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;" }[c])); }
function paint() {
  flat = [];
  let html = "";
  for (const s of sections) {
    html += "<h3>" + esc(s.title) + "<span>" + s.items.length + "</span></h3><div class='grid'>";
    for (const it of s.items) {
      html += "<div class='cell' data-i='" + flat.length + "' title='" + esc(it.n) + "'>" + it.e + "</div>";
      flat.push(it);
    }
    html += "</div>";
  }
  document.getElementById("body").innerHTML = html || "<p class='muted'>No emoji</p>";
  if (sel >= flat.length) sel = 0;
  mark();
}
function mark() {
  const prev = document.querySelector(".cell.on");
  if (prev) prev.classList.remove("on");
  const cell = document.querySelector(".cell[data-i='" + sel + "']");
  if (cell) { cell.classList.add("on"); cell.scrollIntoView({ block: "nearest" }); }
}
function send() { if (flat[sel]) window.webkit.messageHandlers.macotron.postMessage({ e: flat[sel].e }); }
window.__macotronReceive = (d) => { if (d && d.sections) { sections = d.sections; sel = 0; paint(); } };
document.getElementById("q").oninput = (e) =>
  window.webkit.messageHandlers.macotron.postMessage({ q: e.target.value });
document.getElementById("body").onclick = (e) => {
  const cell = e.target.closest(".cell");
  if (cell) { sel = +cell.dataset.i; send(); }
};
document.onkeydown = (e) => {
  const step = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: COLS, ArrowUp: -COLS }[e.key];
  if (step) {
    const next = sel + step;
    if (next >= 0 && next < flat.length) { sel = next; mark(); }
    e.preventDefault();
  } else if (e.key === "Enter") { send(); e.preventDefault(); }
};
</script>`;

async function openPicker() {
  await load();
  const id = macotron.panel.open({
    id: "emoji-picker",
    title: "Emoji",
    width: 620,
    height: 480,
    glass: "translucent",
    frameless: true,
    closeOnBlur: true,
    html: PANEL_HTML,
  });
  macotron.panel.postMessage(id, { sections: sections() });
  macotron.panel.onMessage(id, (data) => {
    if (!data) return;
    if (typeof data.q === "string") {
      const hits = search(data.q, 96);
      macotron.panel.postMessage(id, {
        sections: data.q.trim() ? [{ title: "Results", items: hits }] : sections(),
      });
    } else if (data.e) {
      // pick() first: close() frees this very callback, so nothing after it runs.
      pick(data.e);
      macotron.panel.close(id);
    }
  });
}

macotron.command("Emoji Picker", "Browse and insert an emoji", openPicker);

macotron.launcher.query("emoji", async (q) => {
  if (q.trim().length < 2) return [];
  await load();
  return search(q, 8).map((it) => ({
    id: it.e,
    title: it.e + "  " + it.n,
    subtitle: it.c,
    onClick: () => pick(it.e),
  }));
});

load();
