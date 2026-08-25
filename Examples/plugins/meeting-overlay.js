macotron.plugin({
    title: "Meeting Overlay",
    description: "Show a full-screen overlay one minute before a timed calendar event, with a QR code to join.",
});

const shown = new Set();

function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
}

async function tick() {
    const now = Date.now();
    const events = await macotron.calendar.upcoming({ hours: 1 });
    for (const event of events) {
        if (event.allDay || shown.has(event.id)) continue;
        const until = event.start - now;
        if (until <= 0 || until > 60000) continue;
        shown.add(event.id);
        const url = event.url || "";
        const html =
            `<style>
body { align-items: center; justify-content: center; text-align: center; gap: 20px; padding: 48px; }
h1 { font-size: 42px; }
#cd { font-size: 22px; }
img { width: 200px; height: 200px; background: #fff; border-radius: 16px; padding: 12px; }
</style>
<h1>${esc(event.title || "Meeting")}</h1>
<p id="cd" class="muted"></p>
${url ? `<button class="primary" onclick='webkit.messageHandlers.macotron.postMessage({url:${JSON.stringify(url)}})'>Join</button>` : ""}
<script>
const start = ${event.start};
function paint() {
  const s = Math.max(0, Math.round((start - Date.now()) / 1000));
  const el = document.getElementById("cd");
  if (el) el.textContent = s ? "starts in " + s + "s" : "starting now";
}
paint();
setInterval(paint, 1000);
</script>`;
        const id = macotron.panel.open({
            id: "meeting:" + event.id,
            title: event.title || "Meeting",
            html,
            glass: true,
            frameless: true,
            fullscreen: true,
            qr: url || undefined,
        });
        if (url) {
            macotron.panel.onMessage(id, (msg) => {
                if (msg && msg.url) {
                    macotron.url.open(msg.url);
                    macotron.panel.close(id);
                }
            });
        }
    }
}

tick();
macotron.every(15000, tick);
