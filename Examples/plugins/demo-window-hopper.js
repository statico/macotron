// APIs: window.getAll, window.focus, panel, command
macotron.plugin({
  title: "Window Hopper",
  description: "Switch to a window by name.",
  permissions: ["accessibility"],
});

macotron.command("Switch Window", "Pick a window and bring it forward", () => {
    const windows = macotron.window.getAll();
    const rows = windows.map((win, index) => {
        const title = (win.title || "Untitled").replace(/[<>&]/g, "");
        const app = (win.app || "App").replace(/[<>&]/g, "");
        return `<button class="block" data-i="${index}"><b>${app}</b> — ${title}</button>`;
    }).join("");

    const id = macotron.panel.open({
        title: "Switch Window",
        width: 420,
        height: 480,
        html: `<input id="q" placeholder="Filter…">
<div id="list" class="grow scroll">${rows || '<p class="muted">No windows</p>'}</div>
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
</script>`,
    });

    macotron.panel.onMessage(id, (data) => {
        if (!data || data.type !== "pick") return;
        const win = windows[data.index];
        if (win) macotron.window.focus(win.id);
        macotron.panel.close(id);
    });
});
