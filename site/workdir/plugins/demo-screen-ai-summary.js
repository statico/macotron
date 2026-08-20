// APIs: keyboard, screen.capture, ai.claude, notify

macotron.plugin({
    title: "Screen Summary",
    description: "Summarize a selected area with Claude.",
    permissions: ["screenRecording"],
});

async function summarizeSelection() {
    macotron.notify.toast("Select the area of the screen you want to summarize", { duration: 4000 });
    try {
        const screenshot = await macotron.screen.capture({ selection: true });
        if (!screenshot) return;
        const summary = await macotron.ai.claude().chat(
            "Describe what is on this screen in a short form.",
            { image: screenshot }
        );
        macotron.notify.show("Screen Summary", summary);
    } catch (err) {
        macotron.notify.toast("Screen summary failed", String(err), { color: "failure" });
    }
}

macotron.keyboard.on("Summarize Screen", "cmd+shift+s", summarizeSelection);
macotron.command("Summarize Screen", "Drag a box and ask Claude what is in it", summarizeSelection);
