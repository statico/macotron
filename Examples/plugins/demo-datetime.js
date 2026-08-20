// demo-datetime.js
// APIs: macotron.command, macotron.clipboard.set, macotron.notify

macotron.plugin({
  title: "Date Stamp",
  description: "Copy the current ISO-8601 timestamp.",
});

macotron.command("Insert ISO Date", "Copy current ISO-8601 timestamp to the clipboard", () => {
    const iso = new Date().toISOString();
    macotron.clipboard.set(iso);
    macotron.notify.toast("Copied", iso, { color: "success" });
});
