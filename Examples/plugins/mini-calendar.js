macotron.plugin({
    title: "Mini Calendar",
    description: "Show today's weekday and date in the menu bar, and browse the month.",
});

const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

// The bottom half is a filled block with the date knocked out of it, so the
// number gets the whole width instead of leaving room for a border.
//
// macOS rasterizes text-anchor="middle" about a point right of true centre
// (measured across every day of the month), so the anchor sits left of the
// middle to land the digits on it.
const MID = 10.1;

function icon(date, ink) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="18" viewBox="0 0 22 18">
<mask id="k">
<rect x="0" y="0" width="22" height="18" fill="white"/>
<rect x="1.8" y="1.8" width="18.4" height="6.9" rx="1.9" fill="black"/>
<text x="${MID}" y="16.3" font-family="Helvetica-Bold" font-size="9.2" text-anchor="middle" fill="black">${date.getDate()}</text>
</mask>
<rect x="0.5" y="0.5" width="21" height="17" rx="3.1" fill="${ink}" mask="url(#k)"/>
<text x="${MID + 0.4}" y="7.35" font-family="Helvetica-Bold" font-size="5.7" text-anchor="middle" fill="${ink}">${DOW[date.getDay()]}</text>
</svg>`;
}

// `cal` right-aligns each day in two columns. Bold today's cell only.
function markToday(text, month, year) {
    const now = new Date();
    if (month !== now.getMonth() + 1 || year !== now.getFullYear()) return text;
    const day = String(now.getDate());
    const pad = day.length === 1 ? " " : "";
    return text.replace(new RegExp("(^|\\s)" + pad + day + "(?=\\s|$)", "m"), "$1<b>" + day + "</b>");
}

async function month(m, y) {
    const r = await macotron.shell.run("cal", ["-h", String(m), String(y)]);
    return markToday(r.stdout.replace(/\s+$/, ""), m, y);
}

let panelId = null;

// The host emits panel:closed whichever way the window went away, so the
// toggle stays honest even when the user closes it with Escape.
macotron.on("panel:closed", (event) => {
    if (event && event.id === panelId) panelId = null;
});

function toggle() {
    if (panelId) {
        macotron.panel.close(panelId);
        panelId = null;
        return;
    }
    open();
}

function open() {
    const id = macotron.panel.open({
        title: "Calendar",
        width: 260,
        height: 250,
        glass: true,
        html: `<style>
#bar { display:flex; align-items:center; gap:8px; }
#bar button { width:auto; flex:none; padding:2px 10px; }
#title { flex:1; text-align:center; font-weight:600; }
/* Shrink-wrap the grid and centre the block, not each line: centring the
   text moves a short last week ("30 31") out from under its weekdays. */
pre { margin:10px auto 0; display:table; font-size:13px; line-height:1.5;
      text-align:left; }
pre b { color:var(--macotron-accent); }
</style>
<div id="bar">
  <button id="prev" class="secondary" type="button">‹</button>
  <div id="title">…</div>
  <button id="next" class="secondary" type="button">›</button>
</div>
<pre id="grid"></pre>
<script>
const send = (d) => window.webkit.messageHandlers.macotron.postMessage(d);
document.getElementById("prev").onclick = () => send({ type: "nav", delta: -1 });
document.getElementById("next").onclick = () => send({ type: "nav", delta: 1 });
document.getElementById("title").onclick = () => send({ type: "nav", delta: 0 });
window.__macotronReceive = (data) => {
  if (!data) return;
  document.getElementById("title").textContent = data.title;
  document.getElementById("grid").innerHTML = data.text;
};
send({ type: "nav", delta: 0 });
</script>`,
    });

    panelId = id;

    const now = new Date();
    let m = now.getMonth() + 1;
    let y = now.getFullYear();

    macotron.panel.onMessage(id, async (data) => {
        if (!data || data.type !== "nav") return;
        if (data.delta === 0) {
            m = now.getMonth() + 1;
            y = now.getFullYear();
        } else {
            m += data.delta;
            if (m > 12) { m = 1; y += 1; }
            if (m < 1) { m = 12; y -= 1; }
        }
        const text = await month(m, y);
        macotron.panel.postMessage(id, { title: text.split("\n")[0].trim(), text });
    });
}

// The month as a web page, so the dropdown can show the grid itself. `cal`
// takes a shell round trip and the menu is built synchronously, so lay the
// weeks out here instead.
function grid(now) {
    const first = new Date(now.getFullYear(), now.getMonth(), 1).getDay();
    const days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    let cells = "";
    for (let i = 0; i < first; i++) cells += "<div></div>";
    for (let d = 1; d <= days; d++) {
        cells += `<div${d === now.getDate() ? ' class="today"' : ""}>${d}</div>`;
    }
    return `<style>
#m { display:grid; grid-template-columns:repeat(7, 1fr); text-align:center;
     font-size:11px; line-height:18px; font-variant-numeric:tabular-nums; }
#m .dow { opacity:0.5; font-size:9px; text-transform:uppercase; }
#m .today { background:Highlight; color:HighlightText; border-radius:9px; }
</style>
<div id="m">${DOW.map((d) => `<div class="dow">${d[0]}${d[1].toLowerCase()}</div>`).join("")}${cells}</div>`;
}

function render() {
    const now = new Date();
    macotron.menubar.status("mini-calendar", {
        title: "",
        svg: icon(now, macotron.system.darkMode() ? "#ffffff" : "#000000"),
        onClick: toggle,
        menu: [
            { title: now.toDateString() },
            { html: grid(now), width: 220, height: 130 },
            "-",
            { title: "Open Calendar…", onClick: () => macotron.app.launch("com.apple.iCal") },
        ],
    });
}

render();
macotron.every(60000, render);

macotron.command("Calendar", "Browse this month", toggle);
