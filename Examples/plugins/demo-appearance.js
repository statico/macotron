macotron.plugin({
    title: "Appearance",
    description: "Toggle system light and dark mode.",
});

macotron.command("Toggle Dark Mode", "Switch system appearance between light and dark", async () => {
    try {
        const r = await macotron.shell.run("/usr/bin/osascript", [
            "-e",
            'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode',
            "-e",
            'tell application "System Events" to tell appearance preferences to get dark mode',
        ]);
        if (r.exitCode !== 0) {
            throw new Error(String(r.stderr || r.stdout || "osascript failed").trim());
        }
        const dark = String(r.stdout).trim() === "true";
        macotron.notify.toast("Appearance", dark ? "Dark" : "Light", { color: "success" });
    } catch (err) {
        macotron.notify.toast("Appearance", String(err), { color: "failure" });
    }
});
