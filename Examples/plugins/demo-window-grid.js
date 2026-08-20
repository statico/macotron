const opts = macotron.plugin({
    title: "Window Grid",
    description: "Drag a grid to place the focused window.",
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

let panelId = null;

macotron.on("panel:closed", (event) => {
    if (event && event.id === panelId) macotron.window.previewFraction(null);
});

function openGrid() {
    const win = macotron.window.focused();
    if (!win) {
        macotron.notify.toast("Window Grid", "No focused window", { color: "warning" });
        return;
    }

    const startCols = clampGrid(opts.columns, 6);
    const startRows = clampGrid(opts.rows, 6);

    const id = macotron.panel.open({
        title: "Window Grid",
        width: 380,
        height: 360,
        glass: "translucent",
        frameless: true,
        closeOnBlur: true,
        html: `<style>
body { padding: 14px; gap: 10px; }
.toolbar { display: flex; gap: 16px; align-items: center; }
.toolbar label { display: flex; align-items: center; gap: 6px; white-space: nowrap; }
.toolbar button { width: 28px; height: 28px; padding: 0; flex: none; }
.toolbar .count { min-width: 1.5em; text-align: center; font-variant-numeric: tabular-nums; }
#grid {
  flex: 1;
  display: grid;
  gap: 3px;
  min-height: 0;
  user-select: none;
  -webkit-user-select: none;
}
.cell {
  border-radius: 4px;
  background: light-dark(rgba(0,0,0,0.08), rgba(255,255,255,0.10));
  pointer-events: none;
}
.cell.on {
  background: color-mix(in srgb, var(--macotron-accent) 55%, transparent);
}
p { margin: 0; }
</style>
<div class="toolbar">
  <label>Columns
    <button type="button" id="colsMinus">−</button>
    <span class="count" id="colsVal"></span>
    <button type="button" id="colsPlus">+</button>
  </label>
  <label>Rows
    <button type="button" id="rowsMinus">−</button>
    <span class="count" id="rowsVal"></span>
    <button type="button" id="rowsPlus">+</button>
  </label>
</div>
<p class="muted">Drag across the grid. Release to place the window.</p>
<div id="grid"></div>
<script>
const grid = document.getElementById("grid");
const colsVal = document.getElementById("colsVal");
const rowsVal = document.getElementById("rowsVal");
let cols = ${startCols};
let rows = ${startRows};
let drag = null;
let hover = null;
function send(payload) {
  window.webkit.messageHandlers.macotron.postMessage(payload);
}
function dbg(msg) { send({ type: "log", msg: msg }); }
function clamp(n) { return Math.max(1, Math.min(20, n)); }
function rebuild() {
  colsVal.textContent = String(cols);
  rowsVal.textContent = String(rows);
  grid.style.gridTemplateColumns = "repeat(" + cols + ", 1fr)";
  grid.style.gridTemplateRows = "repeat(" + rows + ", 1fr)";
  let html = "";
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) html += '<div class="cell" data-c="' + c + '" data-r="' + r + '"></div>';
  }
  grid.innerHTML = html;
  drag = null;
  hover = null;
  send({ type: "preview", clear: true });
}
function cellFromPoint(x, y) {
  const rect = grid.getBoundingClientRect();
  if (x < rect.left || y < rect.top || x >= rect.right || y >= rect.bottom) return null;
  const c = Math.min(cols - 1, Math.max(0, Math.floor((x - rect.left) / rect.width * cols)));
  const r = Math.min(rows - 1, Math.max(0, Math.floor((y - rect.top) / rect.height * rows)));
  return { c, r };
}
function paint(sel) {
  const c0 = sel ? Math.min(sel.c0, sel.c1) : -1;
  const c1 = sel ? Math.max(sel.c0, sel.c1) : -1;
  const r0 = sel ? Math.min(sel.r0, sel.r1) : -1;
  const r1 = sel ? Math.max(sel.r0, sel.r1) : -1;
  grid.querySelectorAll(".cell").forEach((cell) => {
    const c = Number(cell.dataset.c);
    const r = Number(cell.dataset.r);
    cell.classList.toggle("on", !!sel && c >= c0 && c <= c1 && r >= r0 && r <= r1);
  });
}
function applySel(sel, reason) {
  paint(sel);
  send(Object.assign({ type: "preview", cols, rows }, sel));
  if (reason !== "hover") dbg(reason + " " + sel.c0 + "," + sel.r0 + ".." + sel.c1 + "," + sel.r1);
}
function bump(which, delta) {
  if (which === "cols") cols = clamp(cols + delta);
  else rows = clamp(rows + delta);
  rebuild();
}
document.getElementById("colsMinus").onclick = () => bump("cols", -1);
document.getElementById("colsPlus").onclick = () => bump("cols", 1);
document.getElementById("rowsMinus").onclick = () => bump("rows", -1);
document.getElementById("rowsPlus").onclick = () => bump("rows", 1);
function onPointer(x, y, buttons) {
  const hit = cellFromPoint(x, y);
  if (buttons & 1) {
    if (!drag) {
      if (!hit) return;
      hover = null;
      drag = { c0: hit.c, r0: hit.r, c1: hit.c, r1: hit.r };
      applySel(drag, "down");
      return;
    }
    if (!hit || (hit.c === drag.c1 && hit.r === drag.r1)) return;
    drag.c1 = hit.c;
    drag.r1 = hit.r;
    applySel(drag, "drag");
    return;
  }
  if (drag) {
    const sel = Object.assign({ cols, rows }, drag);
    dbg("place " + sel.c0 + "," + sel.r0 + ".." + sel.c1 + "," + sel.r1);
    drag = null;
    send(Object.assign({ type: "place" }, sel));
    return;
  }
  if (!hit) {
    if (!hover) return;
    hover = null;
    paint(null);
    send({ type: "preview", clear: true });
    return;
  }
  if (hover && hover.c0 === hit.c && hover.r0 === hit.r) return;
  hover = { c0: hit.c, r0: hit.r, c1: hit.c, r1: hit.r };
  applySel(hover, "hover");
}
window.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  onPointer(e.clientX, e.clientY, 1);
});
window.addEventListener("mousemove", (e) => onPointer(e.clientX, e.clientY, e.buttons));
window.addEventListener("mouseup", (e) => {
  if (e.button !== 0) return;
  onPointer(e.clientX, e.clientY, 0);
});
rebuild();
</script>`,
    });

    panelId = id;

    function apply(sel) {
        const cols = clampGrid(sel.cols, startCols);
        const rows = clampGrid(sel.rows, startRows);
        return Object.assign({ display: win.display }, cellsToFraction(sel, cols, rows));
    }

    macotron.panel.onMessage(id, (data) => {
        if (!data) return;
        if (data.type === "log") {
            macotron.log("grid " + data.msg);
            return;
        }
        if (data.type === "preview") {
            if (data.clear) macotron.window.previewFraction(null);
            else macotron.window.previewFraction(apply(data));
            return;
        }
        if (data.type !== "place") return;
        macotron.log("grid place");
        macotron.window.previewFraction(null);
        macotron.window.moveToFraction(win.id, apply(data));
        macotron.panel.close(id);
    });
}

macotron.keyboard.on("Place Window", "ctrl+opt+g", openGrid);
macotron.command("Place Window", "Place the focused window with a grid", openGrid);
