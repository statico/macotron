// APIs: command, panel

macotron.plugin({
  title: "Calculator",
  description: "Evaluate an expression as you type.",
});

macotron.command("Calculator", "Evaluate an expression as you type", () => {
    const id = macotron.panel.open({
        title: "Calculator",
        width: 360,
        height: 180,
        html: `<input id="q" class="mono" autofocus placeholder="2 + 2 * 10">
<p id="out" class="muted">Type an expression</p>
<script>
const out = document.getElementById("out");
document.getElementById("q").oninput = (e) => {
  window.webkit.messageHandlers.macotron.postMessage({ type: "calc", expr: e.target.value });
};
window.__macotronReceive = (data) => {
  if (data && data.error) out.textContent = data.error;
  if (data && data.result != null) out.textContent = data.result;
};
</script>`,
    });

    macotron.panel.onMessage(id, (data) => {
        if (!data || data.type !== "calc") return;
        const expr = String(data.expr || "").trim();
        if (!expr) {
            macotron.panel.postMessage(id, { error: "Type an expression" });
            return;
        }
        if (!/^[0-9+\-*/().%\s]+$/.test(expr)) {
            macotron.panel.postMessage(id, { error: "Use numbers and + - * / % ( ) only" });
            return;
        }
        try {
            const result = Function('"use strict"; return (' + expr + ")")();
            if (typeof result !== "number" || !isFinite(result)) {
                macotron.panel.postMessage(id, { error: "…" });
                return;
            }
            macotron.panel.postMessage(id, { result: String(result) });
        } catch {
            macotron.panel.postMessage(id, { error: "…" });
        }
    });
});
