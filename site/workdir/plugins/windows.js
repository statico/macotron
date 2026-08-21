const opts = macotron.plugin({
    title: "Windows",
    description: "Tile the focused window with the keyboard, snap it by dragging to an edge, or switch windows by name.",
    permissions: ["accessibility"],
    options: {
        threshold: { type: "number", label: "Snap edge (px)", default: 20 },
        corner: { type: "number", label: "Snap corner (px)", default: 48 },
        gap: { type: "number", label: "Snap gap (px)", default: 0 },
    },
});

function tile(frame) {
    const win = macotron.window.focused();
    if (win) macotron.window.moveToFraction(win.id, frame);
}

function neighborDisplay(current, delta) {
    const displays = macotron.display.list();
    if (displays.length < 2) return undefined;
    const i = displays.findIndex((d) => d.id === current);
    return displays[(Math.max(i, 0) + delta + displays.length) % displays.length].id;
}

function moveToDisplay(delta) {
    const win = macotron.window.focused();
    if (win) macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 1, h: 1, display: neighborDisplay(win.display, delta) });
}

macotron.keyboard.on("Tile Left", "ctrl+opt+left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("Tile Right", "ctrl+opt+right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("Tile Up", "ctrl+opt+up", () => tile({ x: 0, y: 0, w: 1, h: 0.5 }));
macotron.keyboard.on("Tile Down", "ctrl+opt+down", () => tile({ x: 0, y: 0.5, w: 1, h: 0.5 }));
macotron.keyboard.on("Full Screen", "ctrl+opt+return", () => tile({ x: 0, y: 0, w: 1, h: 1 }));
macotron.keyboard.on("Center", "ctrl+opt+c", () => tile({ x: 0.125, y: 0.125, w: 0.75, h: 0.75 }));
macotron.keyboard.on("Next Display", "ctrl+opt+cmd+right", () => moveToDisplay(1));
macotron.keyboard.on("Previous Display", "ctrl+opt+cmd+left", () => moveToDisplay(-1));

macotron.window.snap({
    enabled: true,
    threshold: opts.threshold,
    corner: opts.corner,
    gap: opts.gap,
    zones: {
        left: { x: 0, y: 0, w: 0.5, h: 1 },
        right: { x: 0.5, y: 0, w: 0.5, h: 1 },
        top: { x: 0, y: 0, w: 1, h: 1 },
        bottom: { x: 0, y: 0.5, w: 1, h: 0.5 },
        tl: { x: 0, y: 0, w: 0.5, h: 0.5 },
        tr: { x: 0.5, y: 0, w: 0.5, h: 0.5 },
        bl: { x: 0, y: 0.5, w: 0.5, h: 0.5 },
        br: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
    },
});

macotron.command("Tile Left Half", "Snap focused window left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Right Half", "Snap focused window right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Full Screen", "Maximize focused window", () => tile({ x: 0, y: 0, w: 1, h: 1 }));
macotron.command("Toggle Window Snap", "Enable or disable drag-to-edge snapping", () => {
    const next = !macotron.window.isSnapEnabled();
    const changed = macotron.window.setSnapEnabled(next);
    macotron.notify.toast("Window Snap", changed ? (next ? "On" : "Off") : "Could not change snapping", {
        color: changed ? "success" : "failure",
    });
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
