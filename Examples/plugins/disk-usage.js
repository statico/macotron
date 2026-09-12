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

// `diskutil info <mount>` prints one "Key:   Value" per line. The -plist form
// carries the same facts wrapped in XML we would have to hand-parse, so the
// plain text is both shorter to read and stable across releases.
function parseDiskutil(text) {
    const info = {};
    for (const line of String(text || "").split("\n")) {
        const m = line.match(/^\s*([^:]+?):\s+(.*?)\s*$/);
        if (m) info[m[1].trim()] = m[2];
    }
    return info;
}

// SMART only exists on real physical drives. Disk images, network shares and
// plenty of USB enclosures report nothing at all, and that is normal -- so a
// missing status reads as "unknown", never as a failing drive.
function smartOf(info) {
    const status = (info && info["SMART Status"]) || "";
    return { status, known: !!status, ok: !status || status === "Verified" };
}

// df names a slice (disk3s1s1) but iostat counts the whole physical device
// (disk3), so trim the slice suffix to join the two readings.
function physicalDisk(id) {
    const m = String(id || "").match(/^disk\d+/);
    return m ? m[0] : "";
}

// iostat's first data row is an average since boot, which says nothing about
// right now -- with `-c 2` the second (last) row is the real one-second
// sample. Disk names come from the first header line and each disk owns three
// columns: KB/t, tps, MB/s.
function parseIostat(text) {
    const lines = String(text || "").split("\n").filter((l) => l.trim());
    const names = lines.length ? lines[0].trim().split(/\s+/) : [];
    // Data rows are digits and dots only, which drops both header lines.
    const data = lines.filter((l) => /^[\s\d.]+$/.test(l));
    if (!names.length || !data.length) return [];
    const nums = data[data.length - 1].trim().split(/\s+/).map(Number);
    const disks = [];
    for (let i = 0; i < names.length; i++) {
        const mb = nums[i * 3 + 2];
        if (!Number.isFinite(mb)) continue;
        disks.push({ name: names[i], kbPerTransfer: nums[i * 3], tps: nums[i * 3 + 1], mbPerSec: mb });
    }
    return disks;
}

async function volumes() {
    const df = await macotron.shell.run("/bin/df", ["-k"]);
    const rows = parseDf(df.stdout);
    for (const row of rows) {
        const info = parseDiskutil((await macotron.shell.run("/usr/sbin/diskutil", ["info", row.path])).stdout);
        row.device = info["Device Identifier"] || "";
        row.smart = smartOf(info);
    }
    return rows;
}

async function refreshHealth() {
    const rows = await volumes();
    macotron.checks(rows.map((r) => ({
        title: r.name,
        ok: r.smart.ok,
        message: r.smart.known
            ? "SMART: " + r.smart.status
            : "No SMART status, which is normal for this kind of volume",
    })));
    return rows;
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
.disk { padding:8px 10px; margin:0 0 6px; border-radius:8px; background:light-dark(rgba(0,0,0,.04),rgba(255,255,255,.06)); }
.disk .top { display:flex; justify-content:space-between; gap:12px; }
.disk .sub { display:flex; justify-content:space-between; gap:12px; margin-top:2px; font-size:11px; color:light-dark(#6e6e73,#98989d); }
.warn { color:light-dark(#c93400,#ff9f0a); }
</style>
<div id="disks"></div>
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
const disks = document.getElementById("disks");

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
  if (data.type === "disks") {
    disks.innerHTML = (data.disks || []).map((d) =>
      '<div class="disk"><div class="top"><span class="name">' + esc(d.name) + '</span><span class="size">' + esc(d.size) + '</span></div>'
      + '<div class="sub"><span class="' + (d.ok ? "" : "warn") + '">' + esc(d.smart) + '</span><span>' + esc(d.io) + '</span></div></div>'
    ).join("");
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
    return '<button class="row' + hot + '" data-path="' + esc(row.path) + '" type="button"><div class="top"><span class="name">' + esc(row.name) + '</span><span class="size">' + esc(row.size) + '</span></div><div class="meter"><b style="width:' + pct.toFixed(1) + '%"></b></div></button>';
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
            // `iostat -c 2` spends a second collecting its sample, so it only
            // ever runs here, when someone is looking at the panel.
            refreshHealth().then(async (vols) => {
                const io = parseIostat((await macotron.shell.run("/usr/sbin/iostat", ["-d", "-w", "1", "-c", "2"])).stdout);
                macotron.panel.postMessage(id, {
                    type: "disks",
                    disks: vols.map((v) => {
                        const d = io.find((x) => x.name === physicalDisk(v.device));
                        return {
                            name: v.name,
                            size: fmt(v.kb) + " of " + fmt(v.total),
                            ok: v.smart.ok,
                            smart: v.smart.known ? "SMART " + v.smart.status : "SMART not reported",
                            io: d ? d.mbPerSec.toFixed(2) + " MB/s · " + d.tps + " tps" : "",
                        };
                    }),
                });
            }).catch(() => {});
            return;
        }
        if (data.type === "open") showDir(String(data.path || ""));
        if (data.type === "back") {
            const parent = parentPath(current, home);
            if (parent) showDir(parent);
        }
    });
});

// The folders an app scatters itself across. Everything here is per-user, so
// nothing needs admin rights and nothing outside the home folder is touched.
const LEFTOVER_DIRS = [
    "Library/Application Support",
    "Library/Caches",
    "Library/Containers",
    "Library/Logs",
    "Library/Preferences",
    "Library/Saved Application State",
];

// Only a reverse-DNS name can be traced back to an app. Anything else in these
// folders -- a vendor name, a stray file -- is counted and left alone, because
// guessing at an owner is how a cleaner eats somebody's data.
function bundleIdOf(name) {
    const id = String(name || "").replace(/\.(plist|savedState|binarycookies)$/, "");
    return /^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9_-]*){2,}$/.test(id) ? id : "";
}

// Spotlight knows every installed app; app.list() only knows the ones running
// right now, so it tops up anything Spotlight has not indexed.
async function installedIds() {
    const ids = new Set();
    for (const app of macotron.app.list() || []) if (app.bundleID) ids.add(app.bundleID);
    const found = await macotron.shell.run("/usr/bin/mdfind", ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]);
    const apps = String(found.stdout || "").split("\n").filter(Boolean);
    if (apps.length) {
        // One mdls over every app beats one mdfind per candidate id.
        const out = await macotron.shell.run("/usr/bin/mdls", ["-name", "kMDItemCFBundleIdentifier"].concat(apps));
        const re = /kMDItemCFBundleIdentifier\s*=\s*"([^"]+)"/g;
        let m;
        while ((m = re.exec(String(out.stdout || "")))) ids.add(m[1]);
    }
    return ids;
}

async function leftovers(home) {
    const ids = await installedIds();
    // With Spotlight switched off the installed list comes back nearly empty,
    // which would paint every app on the Mac as uninstalled. Refuse to guess.
    if (ids.size < 20) {
        return { rows: [], skipped: 0, error: "Could not read the list of installed apps, so nothing here is safe to judge." };
    }
    const rows = [];
    let skipped = 0;
    for (const dir of LEFTOVER_DIRS) {
        const base = home + "/" + dir;
        if (!macotron.fs.exists(base)) continue;
        for (const name of macotron.fs.list(base) || []) {
            if (name.charAt(0) === ".") continue;
            const id = bundleIdOf(name);
            if (!id) {
                skipped++;
                continue;
            }
            // Apple's own files ship with the OS; no removable app owns them.
            if (id.indexOf("apple") >= 0) continue;
            if (ids.has(id)) continue;
            rows.push({ id, where: dir, path: base + "/" + name });
        }
    }
    if (rows.length) {
        const du = await macotron.shell.run("/usr/bin/du", ["-sk"].concat(rows.map((r) => r.path)));
        const sizes = {};
        for (const line of String(du.stdout || "").split("\n")) {
            const m = line.match(/^\s*(\d+)\s+(.*)$/);
            if (m) sizes[m[2]] = Number(m[1]);
        }
        for (const row of rows) row.kb = sizes[row.path] || 0;
        rows.sort((a, b) => b.kb - a.kb);
    }
    return { rows, skipped, error: "" };
}

// Finder's delete moves to the Trash, so every removal stays recoverable -- an
// rm here would be unforgivable. The paths ride in as osascript arguments
// rather than inside the script text, so a quote in a filename cannot turn
// into AppleScript.
function trashScript(paths) {
    return [
        "-e", "on run argv",
        "-e", "set doomed to {}",
        "-e", "repeat with p in argv",
        "-e", "set end of doomed to (POSIX file (p as text)) as alias",
        "-e", "end repeat",
        "-e", 'tell application "Finder" to delete doomed',
        "-e", "end run",
    ].concat(paths);
}

macotron.command("Find Leftover Files", "Find files left behind by apps that are gone", () => {
    const id = macotron.panel.open({
        title: "Leftovers",
        width: 420,
        height: 460,
        glass: true,
        html: `<style>
#lead { margin:0 0 8px; }
.row { display:flex; align-items:flex-start; gap:8px; margin:0 0 6px; padding:8px 10px; border-radius:8px; background:light-dark(rgba(0,0,0,.04),rgba(255,255,255,.06)); }
.row .meta { display:flex; flex-direction:column; flex:1; min-width:0; }
.name { font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.where { font-size:11px; color:light-dark(#6e6e73,#98989d); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.size { font-variant-numeric:tabular-nums; flex:none; color:light-dark(#6e6e73,#98989d); }
#foot { display:flex; align-items:center; justify-content:space-between; gap:8px; }
</style>
<p id="lead" class="muted">Looking for leftovers…</p>
<div id="list" class="grow scroll"></div>
<div id="foot"><span id="note" class="muted"></span><button id="trash" type="button" disabled>Move to Trash</button></div>
<script>
const list = document.getElementById("list");
const lead = document.getElementById("lead");
const note = document.getElementById("note");
const trash = document.getElementById("trash");
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;" }[c]));
}
function picked() {
  return Array.from(list.querySelectorAll("input:checked")).map((b) => b.dataset.path);
}
// Nothing starts checked: removing files is the user's decision, one row at a time.
list.onchange = () => { trash.disabled = picked().length === 0; };
trash.onclick = () => {
  const paths = picked();
  if (!paths.length) return;
  trash.disabled = true;
  window.webkit.messageHandlers.macotron.postMessage({ type: "trash", paths: paths });
};
window.__macotronReceive = (data) => {
  if (!data) return;
  lead.textContent = data.lead || "";
  note.textContent = data.note || "";
  trash.disabled = true;
  list.innerHTML = (data.rows || []).map((row) =>
    '<label class="row"><input type="checkbox" data-path="' + esc(row.path) + '"><span class="meta"><span class="name">' + esc(row.id) + '</span><span class="where">' + esc(row.where) + '</span></span><span class="size">' + esc(row.size) + '</span></label>'
  ).join("") || '<p class="muted">Nothing to clean up</p>';
};
window.webkit.messageHandlers.macotron.postMessage({ type: "start" });
</script>`,
    });

    let found = [];
    let home = "";

    async function scan() {
        if (!home) home = String((await macotron.shell.run("/usr/bin/printenv", ["HOME"])).stdout || "").trim();
        if (!home) return;
        const r = await leftovers(home);
        found = r.rows;
        macotron.panel.postMessage(id, {
            type: "rows",
            rows: found.map((row) => ({ ...row, size: fmt(row.kb) })),
            lead: r.error
                ? r.error
                : found.length
                    ? "These belong to apps that are no longer installed. Check the ones to remove."
                    : "No leftovers found.",
            note: r.skipped ? r.skipped + " entries skipped: no app could be named for them" : "",
        });
    }

    macotron.panel.onMessage(id, async (data) => {
        if (!data) return;
        if (data.type === "start") return scan();
        if (data.type !== "trash") return;
        // The panel is web content, so its message is a request and not an
        // order: only paths this scan actually found may move, and the user
        // still has to say yes in a native dialog.
        const known = new Set(found.map((r) => r.path));
        const paths = (data.paths || []).map(String).filter((p) => known.has(p));
        if (!paths.length) return;
        if (!macotron.confirm("Move " + paths.length + " item(s) to the Trash?\n\nThey stay recoverable from the Trash.")) return;
        const r = await macotron.shell.run("/usr/bin/osascript", trashScript(paths));
        const failed = r.exitCode !== 0;
        macotron.notify.toast(
            "Leftovers",
            failed ? "Could not move everything to the Trash" : paths.length + " item(s) moved to the Trash",
            failed ? { color: "error" } : {});
        scan();
    });
});

// Volume health is worth knowing without opening anything, and df plus a
// diskutil call per volume is cheap enough to pay once at load. A mock or a
// sandbox without these tools must not take the plugin down with it.
refreshHealth().catch(() => {});
