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
  });
  macotron.checks([{
    title: "Interface",
    ok: !!r.name,
    message: r.name || "No network interface is carrying traffic",
  }]);
}

function refreshPing() {
  const r = macotron.network.ping();
  pingMs = r && r.ms != null ? r.ms : null;
}

refreshPing();
paint();
macotron.every(2000, paint);
macotron.every(12_000, () => {
  refreshPing();
  paint();
});
