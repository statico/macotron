macotron.plugin({
  title: "Network Stats",
  description: "Show network speed and ping in the menu bar.",
});

function fmt(n) {
  n = Math.abs(n);
  if (n < 1000) return String(Math.round(n));
  const unit = n < 1e6 ? [1e3, "K"] : n < 1e9 ? [1e6, "M"] : [1e9, "G"];
  const scaled = n / unit[0];
  if (scaled >= 10) return Math.round(scaled) + unit[1];
  const t = scaled.toFixed(1);
  return (t.endsWith(".0") ? t.slice(0, -2) : t) + unit[1];
}

let prev = {};
let prevAt = 0;
let pingMs = null;

const SESSION_KEY = "network-path.session";

function today() {
  return new Date().toISOString().slice(0, 10);
}

// A reload wipes plugin state, but the day's data total is the sort of number a
// user expects to keep counting, so it lives in localStorage. A stamp from an
// earlier day is somebody else's total: start over instead of showing it.
function loadSession() {
  try {
    const saved = JSON.parse(localStorage.getItem(SESSION_KEY) || "null");
    if (saved && saved.day === today()) return saved;
  } catch (e) {}
  return { day: today(), in: 0, out: 0 };
}

let session = loadSession();

function saveSession() {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch (e) {}
}

// nettop rows look like `name.pid,bytes_in,bytes_out,`: the header has no pid,
// the trailing comma leaves an empty field, and a process name may hold dots of
// its own ("com.apple.WebKit.Networking.421"), so the pid is whatever follows
// the last one. Anything that does not end in a number is not a process row.
function parseNettop(text) {
  const rows = [];
  for (const line of String(text || "").split("\n")) {
    const parts = line.split(",");
    if (parts.length < 3) continue;
    const dot = parts[0].lastIndexOf(".");
    const pid = dot < 0 ? "" : parts[0].slice(dot + 1);
    if (!/^\d+$/.test(pid)) continue;
    const bytesIn = Number(parts[1]);
    const bytesOut = Number(parts[2]);
    if (!Number.isFinite(bytesIn) || !Number.isFinite(bytesOut)) continue;
    rows.push({ name: parts[0].slice(0, dot), pid: Number(pid), bytesIn, bytesOut });
  }
  return rows;
}

let top = [];
let topPrev = null;

// nettop reports lifetime totals per process, so a single sample only says who
// has ever talked. Two samples ten seconds apart say who is talking now, which
// is the question the menu answers. It is a subprocess, hence the slow poll.
async function pollTop() {
  let out = "";
  try {
    const r = await macotron.shell.run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]);
    out = r && r.stdout;
  } catch (e) {
    return;
  }
  const was = topPrev;
  const now = {};
  const moving = [];
  for (const row of parseNettop(out)) {
    const key = row.name + "." + row.pid;
    now[key] = { in: row.bytesIn, out: row.bytesOut };
    const prior = was && was[key];
    if (!prior) continue;
    const down = Math.max(0, row.bytesIn - prior.in);
    const up = Math.max(0, row.bytesOut - prior.out);
    if (down + up > 0) moving.push({ name: row.name, down, up });
  }
  topPrev = now;
  moving.sort((a, b) => b.down + b.up - (a.down + a.up));
  top = moving.slice(0, 5);
}

function menu() {
  const rows = [
    { title: "Today: ↓" + fmt(session.in) + "B ↑" + fmt(session.out) + "B", icon: "calendar" },
    "-",
  ];
  if (!top.length) {
    rows.push({ title: "Measuring per-process traffic…" });
    return rows;
  }
  for (const t of top) {
    rows.push({ title: t.name + " — ↓" + fmt(t.down) + "B ↑" + fmt(t.up) + "B" });
  }
  return rows;
}

// Picking the first interface that has an IP lands on ap1 or an anpi link,
// which carry no traffic and read as a permanent zero. Measure every interface
// and report whichever is actually moving bytes right now, so a VPN or a
// tethered link takes over on its own.
function rates() {
  const rows = macotron.network.counters() || [];
  const now = Date.now();
  const dt = prevAt && now > prevAt ? (now - prevAt) / 1000 : 0;
  let best = null;
  let busiest = null;
  for (const row of rows) {
    const was = prev[row.name];
    const down = was && dt > 0 ? Math.max(0, (row.bytesIn - was.in) / dt) : 0;
    const up = was && dt > 0 ? Math.max(0, (row.bytesOut - was.out) / dt) : 0;
    if (!best || down + up > best.down + best.up) best = { name: row.name, down, up };
    if (!busiest || row.bytesIn + row.bytesOut > busiest.bytesIn + busiest.bytesOut) busiest = row;
    // Same reason the rates clamp at zero: an interface that dropped or a Mac
    // that rebooted restarts its counters, and that dip is not traffic. Only
    // the growth since the last sample belongs in the day's total.
    if (was) {
      session.in += Math.max(0, row.bytesIn - was.in);
      session.out += Math.max(0, row.bytesOut - was.out);
    }
    prev[row.name] = { in: row.bytesIn, out: row.bytesOut };
  }
  prevAt = now;
  // Idle, or the very first sample: name the link with the most traffic to date
  // rather than whichever happened to sort first.
  if (busiest && (!best || best.down + best.up === 0)) {
    return { name: busiest.name, down: 0, up: 0 };
  }
  return best || { name: "", down: 0, up: 0 };
}

function paint() {
  const r = rates();
  macotron.menubar.status("network-path", {
    title: "↓" + fmt(r.down) + " ↑" + fmt(r.up),
    subtitle: pingMs == null ? "—" : Math.round(pingMs) + " ms",
    secondary: true,
    sfSymbol: "network",
    // Rates change width as they cross 1K/1M, which shoves every item to the
    // left of it around. Hold a width that fits the widest reading.
    minWidth: 96,
    menu: menu(),
  });
  macotron.checks([{
    title: "Interface",
    ok: !!r.name,
    message: r.name || "No network interface is carrying traffic",
  }]);
}

async function refreshPing() {
  const r = await macotron.network.ping();
  pingMs = r && r.ms != null ? r.ms : null;
}

refreshPing().then(paint);
pollTop().then(paint);
paint();
macotron.every(2000, paint);
macotron.every(12_000, () => refreshPing().then(paint));
// One slow tick for both the subprocess and the write: saving the running
// total every 2s would be a lot of churn for a number that moves slowly.
macotron.every(10_000, () => {
  saveSession();
  pollTop().then(paint);
});
// The load-time stamp check already covers a Mac that slept through midnight;
// this is for the one that stayed awake.
macotron.at("00:00", () => {
  session = { day: today(), in: 0, out: 0 };
  saveSession();
});
