// demo-ai-chat.js
// APIs: macotron.command, macotron.panel.open, macotron.panel.onMessage, macotron.panel.postMessage, macotron.ai.claude

macotron.command("AI Chat", "Open a small Claude chat panel", () => {
    const id = macotron.panel.open({
        title: "AI Chat",
        width: 420,
        height: 480,
        html: `<!DOCTYPE html><html><body style="font:14px system-ui;margin:12px">
<textarea id="q" rows="3" style="width:100%" placeholder="Ask…"></textarea>
<button id="go">Send</button>
<pre id="out" style="white-space:pre-wrap"></pre>
<script>
document.getElementById("go").onclick = () => {
  const text = document.getElementById("q").value;
  window.webkit.messageHandlers.macotron.postMessage({ type: "chat", text });
};
window.__macotronReceive = (data) => {
  if (data && data.reply != null) document.getElementById("out").textContent = data.reply;
  if (data && data.error) document.getElementById("out").textContent = "Error: " + data.error;
};
</script></body></html>`,
    });

    macotron.panel.onMessage(id, async (data) => {
        if (!data || data.type !== "chat") return;
        try {
            const reply = await macotron.ai.claude().chat(String(data.text || ""));
            macotron.panel.postMessage(id, { reply });
        } catch (err) {
            macotron.panel.postMessage(id, { error: String(err) });
        }
    });
});
