const opts = macotron.plugin({
    title: "Window Controls",
    description: "Tile the focused window with the keyboard, snap it by dragging to an edge, or switch windows by name.",
    permissions: ["accessibility"],
    options: {
        threshold: { type: "number", label: "Snap edge (px)", default: 20 },
        corner: { type: "number", label: "Snap corner (px)", default: 80 },
        gap: {
            type: "number",
            label: "Gap (px)",
            default: 0,
            min: 0,
            max: 40,
            help: "Padding between a tiled window and the screen edge or its neighbor.",
        },
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
    macotron.window.moveToFraction(win.id, Object.assign({ display, gap: opts.gap }, frames[frameIndex]));
}

function neighborDisplay(current, delta) {
    const displays = macotron.display.list();
    if (displays.length < 2) return undefined;
    const i = displays.findIndex((d) => d.id === current);
    return displays[(Math.max(i, 0) + delta + displays.length) % displays.length].id;
}

function moveToDisplay(delta) {
    const win = macotron.window.focused();
    if (win) {
        macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 1, h: 1, display: neighborDisplay(win.display, delta), gap: opts.gap });
    }
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
    macotron.notify.toast("Window Snap", changed ? (next ? "on" : "off") : "Could not change snapping", {
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

// The wheel places the eight compass zones plus two middles. LAYOUTS.quarters
// is exactly the halves-and-corners set drawn honestly -- LAYOUTS.halves.top is
// deliberately the whole screen so a drag to the top edge maximizes, which is
// wrong for a menu segment labelled "top half".
const RADIAL_FRAMES = Object.assign({}, LAYOUTS.quarters, {
    center: { x: 0.125, y: 0.125, w: 0.75, h: 0.75 },
    full: { x: 0, y: 0, w: 1, h: 1 },
});

// Pointer offset from the wheel centre to a zone name. Self-contained on
// purpose: the panel injects this function verbatim with toString(), so the
// highlight the user sees and the window that moves can never disagree. The
// dead zone is the inner disc, split so its top half maximizes and its bottom
// half centres; RADIAL_INNER below has to stay in step with the 40 here.
function radialZone(dx, dy) {
    const ZONES = ["right", "br", "bottom", "bl", "left", "tl", "top", "tr"];
    if (dx * dx + dy * dy < 40 * 40) return dy < 0 ? "full" : "center";
    // Rounding to the nearest 45 degrees puts each direction in the middle of
    // its wedge, and the modulo folds the 337.5-360 sliver back onto east.
    const deg = ((Math.atan2(dy, dx) * 180) / Math.PI + 360) % 360;
    return ZONES[Math.round(deg / 45) % 8];
}

function openRadial() {
    // macotron.window.focused() skips Macotron's own windows, so the panel
    // taking key focus does not cost us the target window.
    if (!macotron.window.focused()) {
        macotron.notify.toast("Radial Menu", "No focused window", { color: "warning" });
        return;
    }

    const id = macotron.panel.open({
        title: "Radial Menu",
        width: 240,
        height: 240,
        glass: "translucent",
        frameless: true,
        closeOnBlur: true,
        fullscreen: false,
        html: `<style>
body { padding: 0; margin: 0; display: flex; align-items: center; justify-content: center; user-select: none; -webkit-user-select: none; }
svg { display: block; }
.seg { fill: light-dark(rgba(0,0,0,0.06), rgba(255,255,255,0.10)); stroke: light-dark(rgba(0,0,0,0.10), rgba(255,255,255,0.14)); stroke-width: 1; }
.seg.on { fill: color-mix(in srgb, var(--macotron-accent) 60%, transparent); }
text { fill: var(--macotron-label); font-size: 10px; text-anchor: middle; dominant-baseline: middle; pointer-events: none; }
</style>
<svg id="wheel" width="240" height="240" viewBox="0 0 240 240"></svg>
<script>
${radialZone.toString()}
const RADIAL_INNER = 40;
const CX = 120, CY = 120, OUTER = 112;
const wheel = document.getElementById("wheel");
const point = (r, deg) => [CX + r * Math.cos(deg * Math.PI / 180), CY + r * Math.sin(deg * Math.PI / 180)];
let parts = "";
// One donut wedge per compass direction, each centred on its own angle so the
// drawing matches what radialZone() decides.
for (let i = 0; i < 8; i++) {
  const a0 = i * 45 - 22.5, a1 = i * 45 + 22.5;
  const [ix0, iy0] = point(RADIAL_INNER, a0), [ox0, oy0] = point(OUTER, a0);
  const [ox1, oy1] = point(OUTER, a1), [ix1, iy1] = point(RADIAL_INNER, a1);
  const d = "M" + ix0 + " " + iy0 + "L" + ox0 + " " + oy0 +
    "A" + OUTER + " " + OUTER + " 0 0 1 " + ox1 + " " + oy1 +
    "L" + ix1 + " " + iy1 + "A" + RADIAL_INNER + " " + RADIAL_INNER + " 0 0 0 " + ix0 + " " + iy0 + "Z";
  const [lx, ly] = point((RADIAL_INNER + OUTER) / 2, i * 45);
  parts += '<path class="seg" data-zone="' + radialZone(lx - CX, ly - CY) + '" d="' + d + '"></path>' +
    '<text x="' + lx + '" y="' + ly + '">' + ["Right","↘","Bottom","↙","Left","↖","Top","↗"][i] + "</text>";
}
// The inner disc is the dead zone: top half maximizes, bottom half centres.
parts += '<path class="seg" data-zone="full" d="M' + (CX - RADIAL_INNER) + ' ' + CY + 'A' + RADIAL_INNER + ' ' + RADIAL_INNER + ' 0 0 1 ' + (CX + RADIAL_INNER) + ' ' + CY + 'Z"></path>' +
  '<path class="seg" data-zone="center" d="M' + (CX - RADIAL_INNER) + ' ' + CY + 'A' + RADIAL_INNER + ' ' + RADIAL_INNER + ' 0 0 0 ' + (CX + RADIAL_INNER) + ' ' + CY + 'Z"></path>' +
  '<text x="' + CX + '" y="' + (CY - 18) + '">Max</text><text x="' + CX + '" y="' + (CY + 18) + '">Center</text>';
wheel.innerHTML = parts;
let zone = null;
function highlight(next) {
  if (next === zone) return;
  zone = next;
  wheel.querySelectorAll(".seg").forEach((p) => p.classList.toggle("on", p.dataset.zone === zone));
}
window.addEventListener("mousemove", (e) => highlight(radialZone(e.clientX - CX, e.clientY - CY)));
window.addEventListener("click", (e) => {
  window.webkit.messageHandlers.macotron.postMessage({ type: "pick", zone: radialZone(e.clientX - CX, e.clientY - CY) });
});
</script>`,
    });

    macotron.panel.onMessage(id, (data) => {
        if (!data || data.type !== "pick") return;
        macotron.panel.close(id);
        const frame = RADIAL_FRAMES[data.zone];
        if (frame) cycle("radial:" + data.zone, [frame], 0);
    });
}

macotron.keyboard.on("Radial Menu", "ctrl+opt+space", openRadial);
macotron.command("Radial Menu", "Pick a tiling zone from a wheel at the pointer", openRadial);
