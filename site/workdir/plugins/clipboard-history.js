macotron.plugin({
  title: "Clipboard History",
  description: "Search recent clipboard items from the launcher and paste one.",
});

macotron.command("Clipboard History", "Show recent clipboard text", () => {
    macotron.log(macotron.clipboard.history().slice(0, 10));
});
