const opts = macotron.plugin({
    title: "Window Controls",
    description: "Tile the focused window with the keyboard, snap it by dragging to an edge, or switch windows by name.",
    permissions: ["accessibility"],
    options: {
        threshold: { type: "number", label: "Snap edge (px)", default: 20 },
        corner: { type: "number", label: "Snap corner (px)", default: 80 },
        gap: { type: "number", label: "Snap gap (px)", default: 0 },
        snapLayout: {
            type: "dropdown",
            label: "Snap zones",
            default: "halves",
            choices: [
                { value: "halves", label: "Halves" },
                { value: "thirds", label: "Thirds" },
                { value: "quarters", label: "Quarters" },
            ],
        },
        snapModifier: {
            type: "dropdown",
            label: "Alternate snap key",
            help: "Hold this while dragging to snap to the alternate zones instead.",
            default: "shift",
            choices: [
                { value: "none", label: "None" },
                { value: "shift", label: "Shift" },
                { value: "ctrl", label: "Control" },
                { value: "opt", label: "Option" },
                { value: "cmd", label: "Command" },
            ],
        },
        snapModifierLayout: {
            type: "dropdown",
            label: "Alternate snap zones",
            help: "Used while the key above is held.",
            default: "thirds",
            choices: [
                { value: "halves", label: "Halves" },
                { value: "thirds", label: "Thirds" },
                { value: "quarters", label: "Quarters" },
            ],
        },
        cycleDisplays: {
            type: "boolean",
            label: "Cycle through displays",
            default: false,
        },
    },
});

const LAYOUTS = {
    halves: {
        left: { x: 0, y: 0, w: 0.5, h: 1 },
        right: { x: 0.5, y: 0, w: 0.5, h: 1 },
        top: { x: 0, y: 0, w: 1, h: 1 },
        bottom: { x: 0, y: 0.5, w: 1, h: 0.5 },
        tl: { x: 0, y: 0, w: 0.5, h: 0.5 },
        tr: { x: 0.5, y: 0, w: 0.5, h: 0.5 },
        bl: { x: 0, y: 0.5, w: 0.5, h: 0.5 },
        br: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
    },
    thirds: {
        left: { x: 0, y: 0, w: 1 / 3, h: 1 },
        right: { x: 2 / 3, y: 0, w: 1 / 3, h: 1 },
        top: { x: 1 / 3, y: 0, w: 1 / 3, h: 1 },
        bottom: { x: 0, y: 2 / 3, w: 1, h: 1 / 3 },
        tl: { x: 0, y: 0, w: 1 / 3, h: 0.5 },
        tr: { x: 2 / 3, y: 0, w: 1 / 3, h: 0.5 },
        bl: { x: 0, y: 0.5, w: 1 / 3, h: 0.5 },
        br: { x: 2 / 3, y: 0.5, w: 1 / 3, h: 0.5 },
    },
    quarters: {
        left: { x: 0, y: 0, w: 0.5, h: 1 },
        right: { x: 0.5, y: 0, w: 0.5, h: 1 },
        top: { x: 0, y: 0, w: 1, h: 0.5 },
        bottom: { x: 0, y: 0.5, w: 1, h: 0.5 },
        tl: { x: 0, y: 0, w: 0.5, h: 0.5 },
        tr: { x: 0.5, y: 0, w: 0.5, h: 0.5 },
        bl: { x: 0, y: 0.5, w: 0.5, h: 0.5 },
        br: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
    },
};

function layoutNamed(name) {
    return LAYOUTS[name] || LAYOUTS.halves;
}

const LEFT_HALF = { x: 0, y: 0, w: 0.5, h: 1 };
const RIGHT_HALF = { x: 0.5, y: 0, w: 0.5, h: 1 };
const TOP_HALF = { x: 0, y: 0, w: 1, h: 0.5 };
const BOTTOM_HALF = { x: 0, y: 0.5, w: 1, h: 0.5 };
const FIRST_THIRD = { x: 0, y: 0, w: 1 / 3, h: 1 };
const CENTER_THIRD = { x: 1 / 3, y: 0, w: 1 / 3, h: 1 };
const LAST_THIRD = { x: 2 / 3, y: 0, w: 1 / 3, h: 1 };
const FIRST_TWO_THIRDS = { x: 0, y: 0, w: 2 / 3, h: 1 };
const LAST_TWO_THIRDS = { x: 1 / 3, y: 0, w: 2 / 3, h: 1 };

let lastCycle = { name: "", windowId: null, frameIndex: -1 };

function cycle(name, frames, start) {
    const win = macotron.window.focused();
    if (!win) return;
    const displays = macotron.display.list();
    let displayIndex = Math.max(0, displays.findIndex((d) => d.id === win.display));
    const same = lastCycle.name === name && lastCycle.windowId === win.id;
    let frameIndex = start || 0;
    if (same) {
        frameIndex = lastCycle.frameIndex + 1;
        if (frameIndex >= frames.length) {
            frameIndex = 0;
            if (opts.cycleDisplays && displays.length > 1) {
                displayIndex = (displayIndex + 1) % displays.length;
            }
        }
    }
    lastCycle = { name, windowId: win.id, frameIndex };
    const display = displays[displayIndex] && displays[displayIndex].id;
    macotron.window.moveToFraction(win.id, Object.assign({ display }, frames[frameIndex]));
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

macotron.keyboard.on("Left Half", "ctrl+opt+left", () => cycle("left", [LEFT_HALF, RIGHT_HALF], 0));
macotron.keyboard.on("Right Half", "ctrl+opt+right", () => cycle("right", [RIGHT_HALF, LEFT_HALF], 0));
macotron.keyboard.on("Top Half", "ctrl+opt+up", () => cycle("top", [TOP_HALF, BOTTOM_HALF], 0));
macotron.keyboard.on("Bottom Half", "ctrl+opt+down", () => cycle("bottom", [BOTTOM_HALF, TOP_HALF], 0));
macotron.keyboard.on("Full Screen", "ctrl+opt+return", () => cycle("full", [{ x: 0, y: 0, w: 1, h: 1 }], 0));
macotron.keyboard.on("Center", "ctrl+opt+c", () => cycle("center", [{ x: 0.125, y: 0.125, w: 0.75, h: 0.75 }], 0));
macotron.keyboard.on("Top Left", "ctrl+opt+u", () => cycle("tl", [{ x: 0, y: 0, w: 0.5, h: 0.5 }], 0));
macotron.keyboard.on("Top Right", "ctrl+opt+i", () => cycle("tr", [{ x: 0.5, y: 0, w: 0.5, h: 0.5 }], 0));
macotron.keyboard.on("Bottom Left", "ctrl+opt+j", () => cycle("bl", [{ x: 0, y: 0.5, w: 0.5, h: 0.5 }], 0));
macotron.keyboard.on("Bottom Right", "ctrl+opt+k", () => cycle("br", [{ x: 0.5, y: 0.5, w: 0.5, h: 0.5 }], 0));
macotron.keyboard.on("First Third", "ctrl+opt+d", () => cycle("thirds", [FIRST_THIRD, CENTER_THIRD, LAST_THIRD], 0));
macotron.keyboard.on("Center Third", "ctrl+opt+e", () => cycle("thirds", [CENTER_THIRD, LAST_THIRD, FIRST_THIRD], 0));
macotron.keyboard.on("Last Third", "ctrl+opt+f", () => cycle("thirds", [LAST_THIRD, FIRST_THIRD, CENTER_THIRD], 0));
macotron.keyboard.on("First Two Thirds", "ctrl+opt+t", () => cycle("twothirds", [FIRST_TWO_THIRDS, LAST_TWO_THIRDS], 0));
macotron.keyboard.on("Last Two Thirds", "ctrl+opt+y", () => cycle("twothirds", [LAST_TWO_THIRDS, FIRST_TWO_THIRDS], 0));
macotron.keyboard.on("Next Display", "ctrl+opt+cmd+right", () => moveToDisplay(1));
macotron.keyboard.on("Previous Display", "ctrl+opt+cmd+left", () => moveToDisplay(-1));

const snapOpts = {
    enabled: true,
    threshold: opts.threshold,
    corner: opts.corner,
    gap: opts.gap,
    zones: layoutNamed(opts.snapLayout),
};
if (opts.snapModifier && opts.snapModifier !== "none") {
    snapOpts.modifiers = { [opts.snapModifier]: layoutNamed(opts.snapModifierLayout) };
}
macotron.window.snap(snapOpts);

macotron.command("Tile Left Half", "Snap focused window left", () => cycle("left", [LEFT_HALF, RIGHT_HALF], 0));
macotron.command("Tile Right Half", "Snap focused window right", () => cycle("right", [RIGHT_HALF, LEFT_HALF], 0));
macotron.command("Tile Full Screen", "Maximize focused window", () => cycle("full", [{ x: 0, y: 0, w: 1, h: 1 }], 0));
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
