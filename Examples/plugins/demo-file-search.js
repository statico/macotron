// APIs: spotlight.search, shell.run, command, panel

macotron.command("Search Files", "Spotlight search and copy the selected path", () => {
    const id = macotron.panel.open({
        title: "Search Files",
        width: 520,
        height: 420,
        html: `<!DOCTYPE html><html><body style="font:13px system-ui;margin:12px">
<input id="q" autofocus placeholder="Search files…" style="width:100%;padding:8px">
<div id="list" style="margin-top:10px"></div>
<script>
let timer;
document.getElementById("q").oninput = (e) => {
  clearTimeout(timer);
  const q = e.target.value.trim();
  timer = setTimeout(() => {
    window.webkit.messageHandlers.macotron.postMessage({ type: "search", q });
  }, 200);
};
document.getElementById("list").onclick = (e) => {
  const row = e.target.closest("[data-path]");
  if (!row) return;
  window.webkit.messageHandlers.macotron.postMessage({ type: "open", path: row.dataset.path });
};
window.__macotronReceive = (data) => {
  if (!data || !data.hits) return;
  document.getElementById("list").innerHTML = data.hits.map((h) =>
    "<div data-path=\\"" + h.path.replace(/"/g, "") + "\\" style=\\"padding:6px 0;cursor:pointer\\"><b>" +
    h.name + "</b><div style=\\"color:#888;font:11px ui-monospace,monospace\\">" + h.path + "</div></div>"
  ).join("") || "<p>No results</p>";
};
</script></body></html>`,
    });

    macotron.panel.onMessage(id, async (data) => {
        if (!data) return;
        if (data.type === "search") {
            try {
                const hits = await macotron.spotlight.search(String(data.q || ""));
                macotron.panel.postMessage(id, { hits: (hits || []).slice(0, 20) });
            } catch (err) {
                macotron.notify.show("Search Files", String(err));
            }
        }
        if (data.type === "open") {
            await macotron.shell.run("/usr/bin/open", ["-R", String(data.path)]);
            macotron.panel.close(id);
        }
    });
});
