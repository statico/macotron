// APIs: command, panel, clipboard.set

macotron.command("Regex Workbench", "Test a regular expression against sample text", () => {
    const id = macotron.panel.open({
        title: "Regex",
        width: 520,
        height: 420,
        html: `<div class="toolbar">
  <input id="pat" class="mono" placeholder="Pattern" autofocus>
  <input id="flags" class="inline mono" value="g" maxlength="8" title="Flags" placeholder="flags">
</div>
<textarea id="src" class="mono grow" placeholder="Sample text"></textarea>
<pre id="out" class="grow scroll muted">Matches appear here</pre>
<script>
function run() {
  const pat = document.getElementById("pat").value;
  const flags = document.getElementById("flags").value;
  const src = document.getElementById("src").value;
  const out = document.getElementById("out");
  try {
    const re = new RegExp(pat, flags);
    const matches = [...src.matchAll(re)].map((m, i) =>
      (i + 1) + ": " + JSON.stringify(m[0]) + (m.length > 1 ? "  groups=" + JSON.stringify(m.slice(1)) : "")
    );
    out.textContent = matches.length ? matches.join("\\n") : "No matches";
    out.classList.toggle("muted", !matches.length);
  } catch (err) {
    out.textContent = String(err);
    out.classList.remove("muted");
  }
}
document.getElementById("pat").oninput = run;
document.getElementById("flags").oninput = run;
document.getElementById("src").oninput = run;
</script>`,
    });
    void id;
});
