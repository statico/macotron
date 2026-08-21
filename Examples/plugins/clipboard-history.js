macotron.plugin({
  title: "Clipboard History",
  description: "Search recent clipboard items from the launcher.",
});

function clip(s, n) {
  s = String(s || "").replace(/\s+/g, " ").trim();
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function timeLabel(ts) {
  return new Date(ts).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function refresh() {
  const items = macotron.clipboard.history().map((item) => ({
    id: item.id,
    title: item.kind === "image" ? "Image" : clip(item.text, 72),
    subtitle: timeLabel(item.ts),
    sfSymbol: item.kind === "image" ? "photo" : "clipboard",
    kind: item.kind === "image" ? "Image" : "Text",
    onClick: () => macotron.clipboard.paste(item.id),
  }));
  macotron.launcher.set("clipboard-history", items);
}

refresh();
macotron.on("clipboard:changed", refresh);
