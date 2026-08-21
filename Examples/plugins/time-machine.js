macotron.plugin({
  title: "Time Machine",
  description: "Show Time Machine backup progress in the menu bar.",
});

function parseTmutil(text) {
  const src = String(text || "");
  const phase = ((src.match(/BackupPhase\s*=\s*([^;\n]+)/) || [])[1] || "")
    .trim()
    .replace(/^"|"$/g, "") || null;
  const percentRaw = (src.match(/Percent\s*=\s*"?(-?[\d.]+)"?/) || [])[1];
  const bytesRaw = (src.match(/^\s*Bytes\s*=\s*"?(-?[\d.]+)"?/m) || [])[1];
  const n = Number(percentRaw);
  let percent = null;
  if (isFinite(n) && n >= 0) percent = n <= 1 ? Math.round(n * 100) : Math.round(n);
  const running = /Running\s*=\s*1/.test(src) || !!(phase && percent != null);
  return {
    phase: phase,
    percent: percent,
    bytes: isFinite(Number(bytesRaw)) ? Number(bytesRaw) : null,
    running: running,
  };
}

async function paint() {
  const r = await macotron.shell.run("/usr/bin/tmutil", ["status"]);
  const s = parseTmutil((r && r.stdout) || "");
  macotron.menubar.status("timemachine", {
    title: s.running && s.percent != null ? "TM " + s.percent + "%" : "TM",
    sfSymbol: "externaldrive.badge.timemachine",
  });
}

paint();
macotron.every(30_000, paint);
