macotron.plugin({
    title: "Meeting Overlay",
    description: "Show a full-screen overlay when a timed calendar event starts, with a QR code to join.",
});

const KEY = "meeting-overlay.shown";

// Dismissals outlive a reload: without this, editing any plugin while a
// meeting is starting puts the overlay back up for one already waved away.
// Events are keyed by their end time so the list prunes itself.
const shown = new Map(Object.entries(JSON.parse(localStorage.getItem(KEY) || "{}")));

function remember(id, until) {
    shown.set(id, until);
    const now = Date.now();
    for (const [key, at] of shown) {
        if (at < now) shown.delete(key);
    }
    localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(shown)));
}

function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
}

async function tick() {
    const now = Date.now();
    const events = await macotron.calendar.upcoming({ hours: 1 });
    for (const event of events) {
        if (event.allDay || shown.has(event.id)) continue;
        const since = now - event.start;
        // A tick can land late (asleep, reload); anything older than the grace
        // window has been missed, not started, so leave it alone.
        if (since < 0 || since > 5 * 60000) continue;
        remember(event.id, event.end);
        const url = event.url || "";
        const html =
            `<style>
body { align-items: center; justify-content: center; text-align: center; gap: 20px; padding: 48px; }
h1 { font-size: 42px; }
#cd { font-size: 22px; }
.row { display: flex; gap: 12px; }
img { width: 200px; height: 200px; background: #fff; border-radius: 16px; padding: 12px; }
</style>
<h1>${esc(event.title || "Meeting")}</h1>
<p id="cd" class="muted">starting now</p>
<div class="row">
${url ? `<button class="primary" onclick='send({ url: ${JSON.stringify(url)} })'>Join</button>` : ""}
<button onclick='send({ close: true })'>Close</button>
</div>
<script>
function send(msg) { webkit.messageHandlers.macotron.postMessage(msg); }
const start = ${event.start};
setInterval(() => {
  const m = Math.round((Date.now() - start) / 60000);
  document.getElementById("cd").textContent = m ? "started " + m + "m ago" : "starting now";
}, 1000);
</script>`;
        const id = macotron.panel.open({
            id: "meeting:" + event.id,
            title: event.title || "Meeting",
            html,
            glass: true,
            frameless: true,
            fullscreen: true,
            escapeCloses: false,
            qr: url || undefined,
        });
        macotron.panel.onMessage(id, (msg) => {
            if (msg && msg.url) macotron.url.open(msg.url);
            macotron.panel.close(id);
        });
    }
}

tick();
macotron.every(15000, tick);
