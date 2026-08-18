// APIs: command, clipboard.set, notify, panel

macotron.command("Calculator", "Evaluate an expression and copy the result", () => {
    const id = macotron.panel.open({
        title: "Calculator",
        width: 360,
        height: 180,
        html: `<!DOCTYPE html><html><body style="font:14px system-ui;margin:16px">
<input id="q" autofocus placeholder="2 + 2 * 10" style="width:100%;padding:8px;font:16px ui-monospace,monospace">
<p id="out" style="margin:12px 0 0;color:#888">Enter an expression</p>
<script>
const out = document.getElementById("out");
document.getElementById("q").onkeydown = (e) => {
  if (e.key !== "Enter") return;
  const expr = e.target.value.trim();
  window.webkit.messageHandlers.macotron.postMessage({ type: "calc", expr });
};
window.__macotronReceive = (data) => {
  if (data && data.error) out.textContent = data.error;
  if (data && data.result != null) out.textContent = data.result;
};
</script></body></html>`,
    });

    macotron.panel.onMessage(id, (data) => {
        if (!data || data.type !== "calc") return;
        const expr = String(data.expr || "").trim();
        if (!/^[0-9+\-*/().%\s]+$/.test(expr) || !expr) {
            macotron.panel.postMessage(id, { error: "Use numbers and + - * / % ( ) only" });
            return;
        }
        try {
            const result = Function('"use strict"; return (' + expr + ")")();
            if (typeof result !== "number" || !isFinite(result)) {
                macotron.panel.postMessage(id, { error: "Not a finite number" });
                return;
            }
            const text = String(result);
            macotron.clipboard.set(text);
            macotron.panel.postMessage(id, { result: text });
            macotron.notify.show("Calculator", text);
        } catch (err) {
            macotron.panel.postMessage(id, { error: String(err) });
        }
    });
});
