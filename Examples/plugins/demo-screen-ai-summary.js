// demo-screen-ai-summary.js
// APIs: macotron.keyboard, macotron.screen.capture, macotron.ai.claude, macotron.notify

macotron.keyboard.on("summarize", "cmd+shift+s", async () => {
    const screenshot = await macotron.screen.capture();
    const summary = await macotron.ai.claude().chat(
        "Describe what is on this screen in a short form.",
        { image: screenshot }
    );
    macotron.notify.show("Screen Summary", summary);
});

macotron.command("Summarize Screen", "Capture screen and ask Claude", async () => {
    const screenshot = await macotron.screen.capture();
    const summary = await macotron.ai.claude().chat(
        "Describe what is on this screen in a short form.",
        { image: screenshot }
    );
    macotron.notify.show("Screen Summary", summary);
});
