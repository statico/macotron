// APIs: window.getAll, app.list, app.switch, panel, command
macotron.requirePermissions(["accessibility"]);

function bundleForAppName(name) {
    const apps = macotron.app.list();
    const exact = apps.find((app) => app.name === name);
    if (exact) return exact.bundleID;
    const lower = name.toLowerCase();
    const fuzzy = apps.find((app) => app.name.toLowerCase() === lower);
    return fuzzy ? fuzzy.bundleID : null;
}

macotron.command("Switch Window", "Pick a window and bring its app forward", () => {
    const windows = macotron.window.getAll();
    const rows = windows.map((win, index) => {
        const title = (win.title || "Untitled").replace(/[<>&]/g, "");
        const app = (win.app || "App").replace(/[<>&]/g, "");
        return `<button data-i="${index}" style="display:block;width:100%;text-align:left;padding:8px 10px;margin:0 0 4px;border:0;border-radius:6px;background:rgba(128,128,128,0.12);font:13px system-ui;cursor:pointer"><b>${app}</b> — ${title}</button>`;
    }).join("");

    const id = macotron.panel.open({
        title: "Switch Window",
        width: 420,
        height: 480,
        html: `<!DOCTYPE html><html><body style="font:13px system-ui;margin:12px">
<input id="q" placeholder="Filter…" style="width:100%;padding:8px;margin-bottom:8px;font:13px system-ui">
<div id="list">${rows || "<p>No windows</p>"}</div>
<script>
const buttons = [...document.querySelectorAll("button")];
document.getElementById("q").oninput = (e) => {
  const q = e.target.value.toLowerCase();
  buttons.forEach((b) => { b.style.display = b.textContent.toLowerCase().includes(q) ? "block" : "none"; });
};
document.getElementById("list").onclick = (e) => {
  const btn = e.target.closest("button");
  if (!btn) return;
  window.webkit.messageHandlers.macotron.postMessage({ type: "pick", index: Number(btn.dataset.i) });
};
</script></body></html>`,
    });

    macotron.panel.onMessage(id, (data) => {
        if (!data || data.type !== "pick") return;
        const win = windows[data.index];
        if (!win) return;
        const bundleID = bundleForAppName(win.app);
        if (bundleID) macotron.app.switch(bundleID);
        macotron.panel.close(id);
    });
});
