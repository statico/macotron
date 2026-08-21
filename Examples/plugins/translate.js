const opts = macotron.plugin({
  title: "Translate",
  description: "Translate the selected text with the on-device model.",
  permissions: ["accessibility"],
  options: {
    locale: { type: "string", label: "Target locale (blank = system)", default: "" },
  },
});

function esc(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

macotron.command("Translate Selection", "Translate the selected text", async () => {
  const text = macotron.ax.selectedText();
  if (!text) {
    macotron.notify.toast("Translate", "No selected text");
    return;
  }
  const target = (opts.locale || "").trim() || macotron.system.locale().language;
  let body = "";
  try {
    body = await macotron.ai.local().chat(text, {
      system: "Translate to " + target + ". Return only the translation.",
    });
  } catch (err) {
    body = err && err.message ? err.message : String(err);
  }
  macotron.panel.open({
    title: "Translate",
    html: "<p>" + esc(text) + "</p><p>" + esc(body) + "</p>",
  });
});
