// APIs: command, panel, clipboard.set

macotron.command("Regex Workbench", "Test a regular expression against sample text", () => {
    const id = macotron.panel.open({
        title: "Regex",
        width: 520,
        height: 420,
        html: `<input id="pat" class="mono" placeholder="pattern">
<label><input id="flags" class="inline mono" value="g" size="4"> flags</label>
<textarea id="src" class="mono grow" placeholder="sample text"></textarea>
<pre id="out" class="grow scroll muted"></pre>
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
</script>`,
    });
    void id;
});
