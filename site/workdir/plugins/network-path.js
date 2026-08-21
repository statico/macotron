macotron.plugin({
  title: "Network Path",
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

function pick(rows) {
  return rows.find((r) => r.ip) || rows[0];
}

let prev = null;
let pingMs = null;

function rates() {
  const iface = pick(macotron.network.counters() || []);
  const now = Date.now();
  let down = 0;
  let up = 0;
  if (iface && prev && prev.name === iface.name && now > prev.t) {
    const dt = (now - prev.t) / 1000;
    down = Math.max(0, (iface.bytesIn - prev.in) / dt);
    up = Math.max(0, (iface.bytesOut - prev.out) / dt);
  }
  if (iface) prev = { name: iface.name, in: iface.bytesIn, out: iface.bytesOut, t: now };
  return { down, up };
}

function paint() {
  const r = rates();
  macotron.menubar.status("network-path", {
    title: "↓" + fmt(r.down) + " ↑" + fmt(r.up),
    subtitle: pingMs == null ? "—" : Math.round(pingMs) + " ms",
    secondary: true,
    sfSymbol: "network",
  });
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
