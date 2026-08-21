macotron.plugin({
  title: "Clipboard History",
  description: "Search recent clipboard items from the launcher.",
});

function clip(s, n) {
  s = String(s || "").replace(/\s+/g, " ").trim();
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function timeLabel(ts) {
  return new Date(ts).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function rowsFromHistory(items) {
  return (items || []).map((item) => ({
    id: item.id,
    title: item.kind === "image" ? "Image" : clip(item.text, 72),
    subtitle: timeLabel(item.ts),
    sfSymbol: item.kind === "image" ? "photo" : "clipboard",
    kind: item.kind === "image" ? "Image" : "Text",
  }));
}

function refresh() {
  macotron.launcher.set(
    "clipboard-history",
    rowsFromHistory(macotron.clipboard.history()).map((row) => {
      row.onClick = () => macotron.clipboard.paste(row.id);
      return row;
    })
  );
}

refresh();
macotron.on("clipboard:changed", refresh);

macotron.command("Clipboard History", "Browse and paste clipboard history", () => {
  const items = rowsFromHistory(macotron.clipboard.history());
  const id = macotron.panel.open({
    title: "Clipboard History",
    width: 520,
    height: 420,
    glass: "translucent",
    frameless: true,
    closeOnBlur: true,
    html: `<style>
#list [data-id] { padding:6px 8px; border-radius:8px; cursor:pointer; }
#list [data-id]:hover { background: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.12)); }
</style>
<input id="q" autofocus placeholder="Filter…">
<div id="list" class="grow scroll"></div>
<script>
let items = ${JSON.stringify(items)};
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;","'":"&#39;" }[c]));
}
function paint() {
  const q = document.getElementById("q").value.toLowerCase();
  document.getElementById("list").innerHTML = items
    .filter((it) => !q || (it.title + " " + (it.subtitle || "")).toLowerCase().includes(q))
    .map((it) => '<div data-id="' + esc(it.id) + '"><b>' + esc(it.title) + '</b><div class="muted">' + esc(it.subtitle || "") + "</div></div>")
    .join("") || '<p class="muted">No items</p>';
}
paint();
window.__macotronReceive = (d) => { if (d && d.items) { items = d.items; paint(); } };
document.getElementById("q").oninput = paint;
document.getElementById("list").onclick = (e) => {
  const row = e.target.closest("[data-id]");
  if (row) window.webkit.messageHandlers.macotron.postMessage({ id: row.dataset.id });
};
</script>`,
  });
  macotron.panel.postMessage(id, { items });
  macotron.panel.onMessage(id, (data) => {
    if (!data || !data.id) return;
    macotron.clipboard.paste(data.id);
    macotron.panel.close(id);
  });
});
