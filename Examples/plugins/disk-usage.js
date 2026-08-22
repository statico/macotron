macotron.plugin({
    title: "Storage",
    description: "See how much space folders in your home folder use.",
});

function fmt(kb) {
    const n = Number(kb) || 0;
    if (n < 1024) return Math.round(n) + " KB";
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10 * 1024 ? 1 : 0) + " MB";
    return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " GB";
}

function volumeName(mount) {
    if (mount === "/" || mount === "/System/Volumes/Data") return "Macintosh HD";
    const parts = mount.split("/").filter(Boolean);
    return parts[parts.length - 1] || mount;
}

function parseDf(text) {
    const rows = [];
    for (const line of String(text || "").split("\n")) {
        const m = line.match(/^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/);
        if (!m) continue;
        const mount = m[6].trim();
        const fs = m[1];
        if (fs === "devfs" || fs.startsWith("map ")) continue;
        const keep = mount === "/" || mount === "/System/Volumes/Data" || mount.startsWith("/Volumes/");
        if (!keep) continue;
        rows.push({
            name: volumeName(mount),
            path: mount,
            kb: Number(m[3]),
            total: Number(m[2]),
            kind: "volume",
        });
    }
    if (rows.some((r) => r.path === "/System/Volumes/Data")) {
        return rows.filter((r) => r.path !== "/");
    }
    return rows;
}

function parseDu(text, dir) {
    const root = String(dir || "").replace(/\/+$/, "") || "/";
    const kids = [];
    let total = 0;
    for (const line of String(text || "").split("\n")) {
        const m = line.match(/^\s*(\d+)\s+(.*)$/);
        if (!m) continue;
        const kb = Number(m[1]);
        const path = m[2];
        const trimmed = path.replace(/\/+$/, "") || "/";
        if (trimmed === root) {
            total = kb;
            continue;
        }
        const name = trimmed.split("/").filter(Boolean).pop() || trimmed;
        kids.push({ name, path: trimmed, kb, kind: "item" });
    }
    kids.sort((a, b) => b.kb - a.kb);
    return { total: total || kids.reduce((s, r) => s + r.kb, 0), rows: kids };
}

function parentPath(path, root) {
    const trimmed = String(path || "").replace(/\/+$/, "") || "/";
    const base = String(root || "").replace(/\/+$/, "");
    if (!base || trimmed === base) return "";
    const parent = trimmed.split("/").slice(0, -1).join("/") || "/";
    if (parent !== base && !parent.startsWith(base + "/")) return "";
    return parent;
}

function folderName(path, home) {
    const trimmed = String(path || "").replace(/\/+$/, "");
    const base = String(home || "").replace(/\/+$/, "");
    if (base && trimmed === base) return "Home";
    return volumeName(path);
}

macotron.command("Disk Usage", "Browse folder sizes in your home folder", () => {
    const id = macotron.panel.open({
        title: "Storage",
        width: 380,
        height: 440,
        glass: true,
        html: `<style>
#bar { display:flex; align-items:center; gap:8px; }
#back { width:auto; flex:none; padding:4px 8px; }
#crumb { font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
#status { display:flex; align-items:center; gap:8px; min-height:18px; }
.spinner { width:12px; height:12px; border:2px solid light-dark(rgba(0,0,0,.12),rgba(255,255,255,.18)); border-top-color:var(--macotron-accent); border-radius:50%; animation:diskspin .7s linear infinite; flex:none; }
@keyframes diskspin { to { transform: rotate(360deg); } }
.row { display:block; width:100%; text-align:left; margin:0 0 6px; padding:9px 10px; }
.row .top { display:flex; justify-content:space-between; gap:12px; }
.name { font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.size { font-variant-numeric:tabular-nums; flex:none; color:light-dark(#6e6e73,#98989d); }
.meter { margin-top:6px; height:5px; border-radius:99px; background:light-dark(rgba(0,0,0,.08),rgba(255,255,255,.12)); overflow:hidden; }
.meter > b { display:block; height:100%; background:var(--macotron-accent); border-radius:inherit; }
.row.hot .meter > b { background:light-dark(#c93400,#ff9f0a); }
.gone { display:none !important; }
</style>
<div id="bar">
  <button id="back" class="secondary gone" type="button">Back</button>
  <div id="crumb">Home</div>
</div>
<div id="status" class="muted"><span class="spinner"></span><span id="msg">Measuring Home…</span></div>
<div id="list" class="grow scroll"></div>
<script>
const list = document.getElementById("list");
const back = document.getElementById("back");
const crumb = document.getElementById("crumb");
const msg = document.getElementById("msg");
const status = document.getElementById("status");

function send(payload) {
  window.webkit.messageHandlers.macotron.postMessage(payload);
}
function busy(text) {
  status.classList.remove("gone");
  status.querySelector(".spinner").classList.remove("gone");
  msg.textContent = text;
}
function idle(text) {
  status.querySelector(".spinner").classList.add("gone");
  msg.textContent = text || "";
  status.classList.toggle("gone", !text);
}
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;" }[c]));
}
back.onclick = () => send({ type: "back" });
list.onclick = (e) => {
  const row = e.target.closest("[data-path]");
  if (!row) return;
  send({ type: "open", path: row.dataset.path });
};
window.__macotronReceive = (data) => {
  if (!data) return;
  if (data.type === "busy") {
    crumb.textContent = data.title || "Storage";
    back.classList.toggle("gone", !!data.root);
    busy(data.message || "Measuring…");
    return;
  }
  if (data.type !== "rows") return;
  crumb.textContent = data.title || "Home";
  back.classList.toggle("gone", !!data.root);
  idle(data.status || "");
  const total = Number(data.total) || 0;
  list.innerHTML = (data.rows || []).map((row) => {
    const denom = Number(row.total) || total;
    const pct = denom > 0 ? Math.min(100, (100 * row.kb) / denom) : 0;
    const hot = pct >= 85 ? " hot" : "";
    return '<button class="row' + hot + '" data-path="' + esc(row.path) + '" type="button"><div class="top"><span class="name">' +
      esc(row.name) + '</span><span class="size">' + esc(row.size) + '</span></div><div class="meter"><b style="width:' +
      pct.toFixed(1) + '%"></b></div></button>';
  }).join("") || '<p class="muted">Nothing to show</p>';
};
send({ type: "start" });
</script>`,
    });

    let seq = 0;
    let current = "";
    let home = "";

    function isRoot(path) {
        return String(path || "").replace(/\/+$/, "") === String(home || "").replace(/\/+$/, "");
    }

    async function showDir(path) {
        const token = ++seq;
        const name = folderName(path, home);
        macotron.panel.postMessage(id, {
            type: "busy",
            path,
            title: name,
            root: isRoot(path),
            message: "Measuring " + name + "…",
        });
        const r = await macotron.shell.run("du", ["-k", "-d", "1", "-x", path]);
        if (token !== seq) return;
        current = path;
        const parsed = parseDu(r.stdout, path);
        const rows = parsed.rows.map((row) => ({ ...row, size: fmt(row.kb) }));
        const err = String(r.stderr || "").trim();
        macotron.panel.postMessage(id, {
            type: "rows",
            path,
            title: name,
            root: isRoot(path),
            total: parsed.total,
            rows,
            status: err
                ? fmt(parsed.total) + " · some folders were skipped"
                : fmt(parsed.total) + (r.exitCode ? " · finished with warnings" : ""),
        });
    }

    macotron.panel.onMessage(id, async (data) => {
        if (!data) return;
        if (data.type === "start") {
            home = String((await macotron.shell.run("/usr/bin/printenv", ["HOME"])).stdout || "").trim();
            if (!home) return;
            showDir(home);
            return;
        }
        if (data.type === "open") showDir(String(data.path || ""));
        if (data.type === "back") {
            const parent = parentPath(current, home);
            if (parent) showDir(parent);
        }
    });
});
