macotron.plugin({
    title: "Apple TV Controls",
    description: "Find Apple TVs on your network and open a remote.",
    help: "Macotron finds Apple TVs over Bonjour, but sending a key needs Companion "
        + "pairing, which is not implemented yet, so the remote reports \"not paired\". "
        + "Discovery holds the app still for about a second, so it runs once per open "
        + "and the result is reused for 30 seconds.",
});

function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
}

function remoteHTML(tvs) {
    if (!tvs.length) {
        return "<p>No Apple TV found. The tvOS Simulator cannot be controlled.</p>";
    }
    const picker = tvs.length > 1
        ? `<select id="tv">${tvs.map((t) => `<option value="${esc(t.id)}">${esc(t.name)}</option>`).join("")}</select>`
        : `<input type="hidden" id="tv" value="${esc(tvs[0].id)}">`;
    return `${picker}
<style>
.pad { position: relative; width: 176px; height: 176px; border-radius: 50%;
  background: color-mix(in srgb, var(--macotron-control) 70%, transparent);
  border: 1px solid var(--macotron-control-border); margin: 8px auto; }
.pad button { position: absolute; width: 44px; height: 44px; border: 0; background: transparent;
  color: var(--macotron-label); font-size: 18px; }
.up { top: 10px; left: 50%; transform: translateX(-50%); }
.down { bottom: 10px; left: 50%; transform: translateX(-50%); }
.left { left: 10px; top: 50%; transform: translateY(-50%); }
.right { right: 10px; top: 50%; transform: translateY(-50%); }
.select { left: 50%; top: 50%; transform: translate(-50%,-50%); width: 58px; height: 58px;
  border-radius: 50%; background: var(--macotron-accent); color: var(--macotron-accent-text); font-size: 13px; }
.row { display: flex; gap: 10px; justify-content: center; }
.row button { min-width: 72px; padding: 10px 12px; border-radius: 12px;
  border: 1px solid var(--macotron-control-border); background: var(--macotron-control);
  color: var(--macotron-control-text); }
select { width: 100%; }
</style>
<div class="pad">
  <button class="up" data-key="up">▲</button>
  <button class="left" data-key="left">◀</button>
  <button class="select" data-key="select">OK</button>
  <button class="right" data-key="right">▶</button>
  <button class="down" data-key="down">▼</button>
</div>
<div class="row">
  <button data-key="menu">Menu</button>
  <button data-key="home">TV</button>
</div>
<div class="row">
  <button data-key="playpause">⏯</button>
</div>
<script>
document.addEventListener("click", (e) => {
  const key = e.target.closest("[data-key]")?.dataset.key;
  if (!key) return;
  const tv = document.getElementById("tv");
  webkit.messageHandlers.macotron.postMessage({ "type":"key", key, id: tv ? tv.value : "" });
});
</script>`;
}

function open() {
    // Discovery parks the main thread for its whole timeout. Do it once when
    // the remote opens, not on every key press.
    const tvs = macotron.appletv.list();
    const id = macotron.panel.open({
        title: "Apple TV",
        width: 280,
        height: 480,
        glass: true,
        html: remoteHTML(tvs),
    });
    let warned = false;
    macotron.panel.onMessage(id, (msg) => {
        if (!msg || msg.type !== "key") return;
        const target = msg.id || (tvs[0] && tvs[0].id);
        if (!target) return;
        const result = macotron.appletv.send(target, msg.key);
        if (result && result.ok) return;
        // Say it once rather than swallowing every press.
        if (warned) return;
        warned = true;
        macotron.notify.toast("Apple TV", result && result.error ? result.error : "Could not send", {
            color: "error",
        });
    });
}

macotron.command("Apple TV Remote", "Remote for Apple TVs on the LAN", open);

macotron.menubar.status("appletv", {
    title: "",
    sfSymbol: "appletvremote.gen4.fill",
    onClick: open,
});
