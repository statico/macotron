// APIs: spotlight.search, shell.run, command, panel

macotron.plugin({
  title: "File Search",
  description: "Spotlight search and copy a path.",
});

macotron.command("Search Files", "Spotlight search and copy the selected path", () => {
    const id = macotron.panel.open({
        title: "Search Files",
        width: 520,
        height: 420,
        html: `<input id="q" autofocus placeholder="Search files…">
<div id="list" class="grow scroll"></div>
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
    h.name + "</b><div class=\\"muted mono\\">" + h.path + "</div></div>"
  ).join("") || "<p class=\\"muted\\">No results</p>";
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
