macotron.command("Clipboard History", "Log recent clipboard text", () => {
    macotron.log(macotron.clipboard.history().slice(0, 10));
});
