macotron.plugin({
  title: "Markdown Preview",
  description: "Preview Markdown from the clipboard in a panel.",
});

function esc(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

function toHtml(src) {
  return String(src || "").split(/\n{2,}/).map((block) => {
    const t = block.trim();
    const h = t.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      const n = h[1].length;
      return "<h" + n + ">" + inline(h[2]) + "</h" + n + ">";
    }
    return "<p>" + inline(t).replace(/\n/g, "<br>") + "</p>";
  }).join("");
}

macotron.command("Markdown from Clipboard", "Preview clipboard markdown", () => {
  macotron.panel.open({ title: "Markdown", html: toHtml(macotron.clipboard.text()) });
});
