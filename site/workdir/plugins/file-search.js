// APIs: spotlight.search, shell.run, command, panel

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

macotron.command("Search Files", "Spotlight search and copy the selected path", () => {
    const id = macotron.panel.open({
        title: "Search Files",
        width: 520,
        height: 420,
        glass: "clear",
        frameless: true,
        html: `<style>
#list [data-path] { padding:6px 8px; border-radius:8px; cursor:pointer; }
#list [data-path]:hover, #list [data-path].sel {
  background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.12));
}
</style>
<input id="q" autofocus placeholder="Search files…">
<div id="list" class="grow scroll"></div>
<script>
${navDelta.toString()}
${clampIndex.toString()}
const list = document.getElementById("list");
let timer;
let selected = 0;
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
function openSel() {
  const row = rows()[selected];
  if (!row) return;
  window.webkit.messageHandlers.macotron.postMessage({ type: "open", path: row.dataset.path });
}
document.getElementById("q").oninput = (e) => {
  clearTimeout(timer);
  const q = e.target.value.trim();
  timer = setTimeout(() => {
    window.webkit.messageHandlers.macotron.postMessage({ type: "search", q });
  }, 200);
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
  window.webkit.messageHandlers.macotron.postMessage({ type: "open", path: row.dataset.path });
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
    openSel();
  }
});
window.__macotronReceive = (data) => {
  if (!data || !data.hits) return;
  selected = 0;
  list.innerHTML = data.hits.map((h) =>
    "<div data-path=\\"" + h.path.replace(/"/g, "") + "\\"><b>" +
    h.name + "</b><div class=\\"muted\\">" + h.path + "</div></div>"
  ).join("") || "<p class=\\"muted\\">No results</p>";
  paintSel();
};
</script>`,
    });

    macotron.panel.onMessage(id, async (data) => {
        if (!data) return;
        if (data.type === "search") {
            try {
                const hits = await macotron.spotlight.search(String(data.q || ""));
                macotron.panel.postMessage(id, { hits: (hits || []).slice(0, 20) });
            } catch (err) {
                macotron.notify.toast("Search Files", String(err), { color: "failure" });
            }
        }
        if (data.type === "open") {
            await macotron.shell.run("/usr/bin/open", ["-R", String(data.path)]);
            macotron.panel.close(id);
        }
    });
});
