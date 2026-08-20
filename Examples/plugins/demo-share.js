macotron.plugin({
  title: "Share",
  description: "Share text or files with the system share sheet and AirDrop.",
});

macotron.command("Share Text", "Share the clipboard text", () => {
  const text = macotron.clipboard.text();
  if (!text) {
    macotron.notify.toast("Share", "Clipboard is empty");
    return;
  }
  macotron.share.open({ text });
});

macotron.command("Share File", "Share a file path from a prompt", () => {
  const path = macotron.prompt("File to share", "~/Desktop/");
  if (!path) return;
  macotron.share.open({ files: [path] });
});

macotron.command("AirDrop File", "AirDrop a file path from a prompt", () => {
  const path = macotron.prompt("File to AirDrop", "~/Desktop/");
  if (!path) return;
  macotron.share.airDrop([path]);
});

macotron.command("Share Services", "List sharing service names", () => {
  macotron.notify.toast("Share", macotron.share.services().join(", ") || "None");
});
