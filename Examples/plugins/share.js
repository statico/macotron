macotron.plugin({
  title: "Share Commands",
  description: "Share clipboard text or a file with the share sheet or AirDrop.",
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
