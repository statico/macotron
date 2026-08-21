macotron.plugin({
  title: "File Search",
  description: "Search files with Spotlight and copy or reveal a path.",
});

function navDelta(key, ctrl) {
  const k = String(key || "");
  if (k === "ArrowUp" || (ctrl && k.toLowerCase() === "p")) return -1;
  if (k === "ArrowDown" || (ctrl && (k === "n" || k === "N" || k === "m" || k === "M"))) return 1;
  return 0;
}

function clampIndex(i, len) {
  if (len <= 0) return 0;
  if (i < 0) return 0;
  if (i >= len) return len - 1;
  return i;
}

macotron.command("Search Files", "Spotlight search and reveal the selected path", () => {
  const id = macotron.panel.open({
    title: "Search Files",
    width: 520,
    height: 420,
    glass: "translucent",
    frameless: true,
    closeOnBlur: true,
    html: `<style>
#status { display:flex; align-items:center; gap:8px; min-height:18px; }
.spinner { width:12px; height:12px; border:2px solid light-dark(rgba(0,0,0,.12),rgba(255,255,255,.18)); border-top-color:var(--macotron-accent); border-radius:50%; animation:spin .7s linear infinite; flex:none; }
@keyframes spin { to { transform: rotate(360deg); } }
.gone { display:none !important; }
#list [data-path] { padding:6px 8px; border-radius:8px; cursor:pointer; }
#list [data-path]:hover, #list [data-path].sel {
  background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.12));
}
</style>
<div style="display:flex;gap:8px;align-items:center">
<input id="q" autofocus placeholder="Search files…" style="flex:1">
<select id="kind">
<option value="">All</option>
<option value="pdf">pdf</option>
<option value="png">png</option>
<option value="jpg">jpg</option>
<option value="jpeg">jpeg</option>
<option value="md">md</option>
<option value="txt">txt</option>
</select>
</div>
<div id="status" class="muted gone"><span class="spinner"></span><span id="msg"></span></div>
<div id="list" class="grow scroll"></div>
<script>
${navDelta.toString()}
${clampIndex.toString()}
const list = document.getElementById("list");
const status = document.getElementById("status");
const msg = document.getElementById("msg");
let timer;
let selected = 0;
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
function kind() { return document.getElementById("kind").value; }
function rows() { return [...list.querySelectorAll("[data-path]")]; }
function paintSel() {
  const all = rows();
  all.forEach((row, i) => row.classList.toggle("sel", i === selected));
  const row = all[selected];
  if (row) row.scrollIntoView({ block: "nearest" });
}
function move(delta) {
  const n = rows().length;
  if (!n) return;
  selected = clampIndex(selected + delta, n);
  paintSel();
}
function searchNow(q) {
  send({ type: "search", q, kind: kind() });
}
function openSel(reveal) {
  const row = rows()[selected];
  if (!row) return;
  send({ type: "open", path: row.dataset.path, reveal: reveal });
}
document.getElementById("q").oninput = (e) => {
  clearTimeout(timer);
  const q = e.target.value.trim();
  if (!q) {
    idle();
    list.innerHTML = "";
    searchNow("");
    return;
  }
  busy("Searching…");
  timer = setTimeout(() => searchNow(q), 200);
};
document.getElementById("kind").onchange = () => {
  const q = document.getElementById("q").value.trim();
  if (!q) return;
  busy("Searching…");
  searchNow(q);
};
list.onmouseover = (e) => {
  const row = e.target.closest("[data-path]");
  if (!row) return;
  selected = rows().indexOf(row);
  paintSel();
};
list.onclick = (e) => {
  const row = e.target.closest("[data-path]");
  if (!row) return;
  send({ type: "open", path: row.dataset.path });
};
document.addEventListener("keydown", (e) => {
  const delta = navDelta(e.key, e.ctrlKey);
  if (delta) {
    e.preventDefault();
    move(delta);
    return;
  }
  if (e.key === "Enter") {
    e.preventDefault();
    const row = rows()[selected];
    if (!row) return;
    if (e.metaKey) send({ type: "copy", path: row.dataset.path });
    else openSel(!e.altKey);
  }
});
window.__macotronReceive = (data) => {
  if (!data || data.type === "busy") return;
  selected = 0;
  const hits = data.hits || [];
  idle();
  list.innerHTML = hits.map((h) =>
    '<div data-path="' + esc(h.path) + '"><b>' + esc(h.name) + '</b><div class="muted">' + esc(h.path) + "</div></div>"
  ).join("") || '<p class="muted">No results</p>';
  paintSel();
};
</script>`,
  });

  let seq = 0;
  macotron.panel.onMessage(id, async (data) => {
    if (!data) return;
    if (data.type === "search") {
      const q = String(data.q || "").trim();
      const token = ++seq;
      if (!q) return;
      try {
        const hits = await macotron.spotlight.search(q, { kind: String(data.kind || "") });
        if (token !== seq) return;
        macotron.panel.postMessage(id, { hits: (hits || []).slice(0, 20) });
      } catch (err) {
        if (token !== seq) return;
        macotron.notify.toast("Search Files", String(err), { color: "failure" });
        macotron.panel.postMessage(id, { hits: [] });
      }
    }
    if (data.type === "copy") {
      macotron.clipboard.set(String(data.path));
      macotron.notify.toast("Copied", String(data.path));
    }
    if (data.type === "open") {
      const path = String(data.path);
      await macotron.shell.run("/usr/bin/open", data.reveal === false ? [path] : ["-R", path]);
      macotron.panel.close(id);
    }
  });
});
