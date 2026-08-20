const opts = macotron.plugin({
    title: "Divvy",
    description: "Drag cells on a grid to place the focused window.",
    permissions: ["accessibility"],
    options: {
        columns: { type: "number", label: "Columns", default: 6 },
        rows: { type: "number", label: "Rows", default: 6 },
    },
});

function clampGrid(n, fallback) {
    const v = Math.round(Number(n));
    if (!Number.isFinite(v) || v < 1) return fallback;
    return Math.min(20, v);
}

function cellsToFraction(sel, cols, rows) {
    const c0 = Math.min(sel.c0, sel.c1);
    const c1 = Math.max(sel.c0, sel.c1);
    const r0 = Math.min(sel.r0, sel.r1);
    const r1 = Math.max(sel.r0, sel.r1);
    return {
        x: c0 / cols,
        y: r0 / rows,
        w: (c1 - c0 + 1) / cols,
        h: (r1 - r0 + 1) / rows,
    };
}

let divvyId = null;

macotron.on("panel:closed", (event) => {
    if (event && event.id === divvyId) macotron.window.previewFraction(null);
});

function openDivvy() {
    const win = macotron.window.focused();
    if (!win) {
        macotron.notify.toast("Divvy", "No focused window", { color: "warning" });
        return;
    }

    const cols = clampGrid(opts.columns, 6);
    const rows = clampGrid(opts.rows, 6);
    const cells = Array.from({ length: cols * rows }, (_, i) => {
        const c = i % cols;
        const r = Math.floor(i / cols);
        return `<div class="cell" data-c="${c}" data-r="${r}"></div>`;
    }).join("");

    const id = macotron.panel.open({
        title: "Divvy",
        width: 360,
        height: 320,
        glass: "translucent",
        frameless: true,
        closeOnBlur: true,
        html: `<style>
body { padding: 14px; gap: 10px; }
#grid {
  flex: 1;
  display: grid;
  grid-template-columns: repeat(${cols}, 1fr);
  grid-template-rows: repeat(${rows}, 1fr);
  gap: 3px;
  min-height: 0;
  user-select: none;
  touch-action: none;
}
.cell {
  border-radius: 4px;
  background: light-dark(rgba(0,0,0,0.08), rgba(255,255,255,0.10));
}
.cell.on {
  background: color-mix(in srgb, var(--macotron-accent) 55%, transparent);
}
p { margin: 0; }
</style>
<p class="muted">Drag across the grid. Release to place the window.</p>
<div id="grid">${cells}</div>
<script>
const grid = document.getElementById("grid");
let drag = null;
function send(payload) {
  window.webkit.messageHandlers.macotron.postMessage(payload);
}
function cellAt(el) {
  const cell = el && el.closest ? el.closest(".cell") : null;
  if (!cell) return null;
  return { c: Number(cell.dataset.c), r: Number(cell.dataset.r) };
}
function paint(sel) {
  const c0 = Math.min(sel.c0, sel.c1);
  const c1 = Math.max(sel.c0, sel.c1);
  const r0 = Math.min(sel.r0, sel.r1);
  const r1 = Math.max(sel.r0, sel.r1);
  grid.querySelectorAll(".cell").forEach((cell) => {
    const c = Number(cell.dataset.c);
    const r = Number(cell.dataset.r);
    cell.classList.toggle("on", c >= c0 && c <= c1 && r >= r0 && r <= r1);
  });
}
grid.addEventListener("pointerdown", (e) => {
  const hit = cellAt(e.target);
  if (!hit) return;
  grid.setPointerCapture(e.pointerId);
  drag = { c0: hit.c, r0: hit.r, c1: hit.c, r1: hit.r };
  paint(drag);
  send(Object.assign({ type: "preview" }, drag));
});
grid.addEventListener("pointermove", (e) => {
  if (!drag) return;
  const hit = cellAt(document.elementFromPoint(e.clientX, e.clientY));
  if (!hit) return;
  if (hit.c === drag.c1 && hit.r === drag.r1) return;
  drag.c1 = hit.c;
  drag.r1 = hit.r;
  paint(drag);
  send(Object.assign({ type: "preview" }, drag));
});
function finish(place) {
  if (!drag) return;
  const sel = drag;
  drag = null;
  if (place) send(Object.assign({ type: "place" }, sel));
  else send({ type: "preview", clear: true });
}
grid.addEventListener("pointerup", () => finish(true));
grid.addEventListener("pointercancel", () => finish(false));
</script>`,
    });

    divvyId = id;

    function apply(sel) {
        return Object.assign({ display: win.display }, cellsToFraction(sel, cols, rows));
    }

    macotron.panel.onMessage(id, (data) => {
        if (!data) return;
        if (data.type === "preview") {
            if (data.clear) macotron.window.previewFraction(null);
            else macotron.window.previewFraction(apply(data));
            return;
        }
        if (data.type !== "place") return;
        macotron.window.previewFraction(null);
        macotron.window.moveToFraction(win.id, apply(data));
        macotron.panel.close(id);
    });
}

macotron.keyboard.on("Divvy", "ctrl+opt+g", openDivvy);
macotron.command("Divvy", "Place the focused window with a grid", openDivvy);
