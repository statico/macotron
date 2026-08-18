// APIs: command, panel, clipboard.set

macotron.command("Regex Workbench", "Test a regular expression against sample text", () => {
    const id = macotron.panel.open({
        title: "Regex",
        width: 520,
        height: 420,
        html: `<!DOCTYPE html><html><body style="font:13px system-ui;margin:14px">
<input id="pat" placeholder="pattern" style="width:100%;padding:6px;font:13px ui-monospace,monospace">
<label style="display:block;margin:8px 0"><input id="flags" value="g" style="width:60px;font:13px ui-monospace,monospace"> flags</label>
<textarea id="src" rows="8" style="width:100%;font:13px ui-monospace,monospace" placeholder="sample text"></textarea>
<pre id="out" style="white-space:pre-wrap;margin-top:10px;min-height:80px"></pre>
<script>
function run() {
  const pat = document.getElementById("pat").value;
  const flags = document.getElementById("flags").value;
  const src = document.getElementById("src").value;
  try {
    const re = new RegExp(pat, flags);
    const matches = [...src.matchAll(re)].map((m, i) =>
      (i + 1) + ": " + JSON.stringify(m[0]) + (m.length > 1 ? "  groups=" + JSON.stringify(m.slice(1)) : "")
    );
    document.getElementById("out").textContent = matches.length ? matches.join("\\n") : "No matches";
  } catch (err) {
    document.getElementById("out").textContent = String(err);
  }
}
document.getElementById("pat").oninput = run;
document.getElementById("flags").oninput = run;
document.getElementById("src").oninput = run;
</script></body></html>`,
    });
    void id;
});
