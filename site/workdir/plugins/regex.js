// APIs: command, panel, clipboard.set

macotron.plugin({
  title: "Regex Workbench",
  description: "Test a regular expression against sample text.",
});

macotron.command("Regex Workbench", "Test a regular expression against sample text", () => {
  const id = macotron.panel.open({
    title: "Regex",
    width: 520,
    height: 420,
    html: `<div class="toolbar">
  <input id="pat" class="mono" placeholder="fox|dog" autofocus>
  <input id="flags" class="inline mono" value="g" maxlength="8" placeholder="gimsuy" title="Flags: g i m s u y d">
</div>
<p class="muted">JavaScript regex, no wrapping slashes. Flags: g i m s u y</p>
<textarea id="src" class="mono grow" placeholder="The quick brown fox jumps over the lazy dog"></textarea>
<pre id="out" class="grow scroll muted">Type a pattern</pre>
<script>
function run() {
  const pat = document.getElementById("pat").value;
  const flags = document.getElementById("flags").value;
  const src = document.getElementById("src").value;
  const out = document.getElementById("out");
  if (!pat) {
    out.textContent = "Type a pattern";
    out.classList.add("muted");
    return;
  }
  if (!src) {
    out.textContent = "Paste sample text";
    out.classList.add("muted");
    return;
  }
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
