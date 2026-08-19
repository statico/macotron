macotron.plugin({
  title: "Clipboard History",
  description: "Log recent clipboard text.",
});

macotron.command("Clipboard History", "Log recent clipboard text", () => {
    macotron.log(macotron.clipboard.history().slice(0, 10));
});
