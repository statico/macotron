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

function remoteHTML() {
    return `<div id="picker"></div>
<div id="status">Looking for Apple TVs<span class="dots"></span></div>
<style>
#status { text-align: center; padding: 24px 8px; color: var(--macotron-secondary-label); }
.dots::after { content: "..."; animation: dots 1.2s steps(4, end) infinite; }
@keyframes dots { 0% { content: ""; } 25% { content: "."; } 50% { content: ".."; } 75% { content: "..."; } }
#remote[hidden] { display: none; }
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
<div id="remote" hidden>
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
</div>
<script>
// The host finds the Apple TVs after the window is already up, so the remote
// starts as a spinner and fills in when the list arrives.
window.addEventListener("message", (e) => {
  const tvs = (e.data && e.data.tvs) || [];
  const status = document.getElementById("status");
  if (!tvs.length) {
    status.textContent = "No Apple TV found. The tvOS Simulator cannot be controlled.";
    return;
  }
  status.hidden = true;
  document.getElementById("remote").hidden = false;
  document.getElementById("picker").innerHTML = tvs.length > 1
    ? '<select id="tv">' + tvs.map((t) =>
        '<option value="' + t.id + '">' + t.name + "</option>").join("") + "</select>"
    : '<input type="hidden" id="tv" value="' + tvs[0].id + '">';
});

document.addEventListener("click", (e) => {
  const key = e.target.closest("[data-key]")?.dataset.key;
  if (!key) return;
  const tv = document.getElementById("tv");
  webkit.messageHandlers.macotron.postMessage({ "type":"key", key, id: tv ? tv.value : "" });
});
</script>`;
}

function open() {
    const id = macotron.panel.open({
        title: "Apple TV",
        width: 280,
        height: 480,
        glass: true,
        html: remoteHTML(),
    });
    // Discovery parks the main thread for its whole timeout, so let the window
    // draw first. The result is reused for 30 seconds by the host.
    let tvs = [];
    setTimeout(() => {
        tvs = macotron.appletv.list().map((t) => ({ id: esc(t.id), name: esc(t.name) }));
        macotron.panel.postMessage(id, { tvs });
    }, 50);
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
