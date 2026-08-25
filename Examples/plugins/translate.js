const systemLocale = macotron.system.locale().language;

const opts = macotron.plugin({
  title: "Translate Selected Text",
  description: "Translate the selected text with Apple Intelligence.",
  permissions: ["accessibility"],
  options: {
    locale: {
      type: "string",
      label: "Target locale",
      placeholder: systemLocale,
      default: "",
    },
  },
});

function esc(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

macotron.command("Translate Selection", "Translate the selected text", async () => {
  const text = await macotron.ax.selectedText();
  if (!text) {
    macotron.notify.toast("Cannot translate", "No selected text", { color: "error" });
    return;
  }
  const target = (opts.locale || "").trim() || systemLocale;
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
    html:
      '<p class="muted">Translation to ' + esc(target) + ":</p>" +
      "<p>" + esc(body) + "</p>" +
      '<p class="muted">' + esc(text) + "</p>",
  });
});
