macotron.plugin({
    title: "Mini Calendar",
    description: "Show today's weekday and date in the menu bar, and browse the month.",
});

const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

function icon(date, ink) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="21" height="18" viewBox="0 0 21 18">
<rect x="1.3" y="2.2" width="18.4" height="14.6" rx="3.2" fill="none" stroke="${ink}" stroke-width="1.3"/>
<path d="M1.3 7.4 H19.7" stroke="${ink}" stroke-width="1.1"/>
<path d="M6.2 1.2 V3.4 M14.8 1.2 V3.4" stroke="${ink}" stroke-width="1.3" stroke-linecap="round"/>
<text x="10.5" y="6.4" font-family="Helvetica-Bold" font-size="4.2" text-anchor="middle" fill="${ink}">${DOW[date.getDay()]}</text>
<text x="10.5" y="15.2" font-family="Helvetica-Bold" font-size="7.8" text-anchor="middle" fill="${ink}">${date.getDate()}</text>
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
pre { margin:10px 0 0; font-size:13px; line-height:1.5; text-align:center; }
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

function render() {
    const now = new Date();
    macotron.menubar.status("mini-calendar", {
        title: "",
        svg: icon(now, macotron.system.darkMode() ? "#ffffff" : "#000000"),
        onClick: open,
        menu: [
            { title: now.toDateString() },
            "-",
            { title: "Open Calendar…", onClick: () => macotron.app.launch("com.apple.iCal") },
        ],
    });
}

render();
macotron.every(60000, render);

macotron.command("Calendar", "Browse this month", open);
