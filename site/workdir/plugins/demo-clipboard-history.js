macotron.plugin({
  title: "Clipboard History",
  description: "Show recent clipboard text.",
});

macotron.command("Clipboard History", "Show recent clipboard text", () => {
    macotron.log(macotron.clipboard.history().slice(0, 10));
});
