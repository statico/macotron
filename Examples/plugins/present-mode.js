// APIs: command, shell.run, notify

macotron.plugin({
    title: "Presenter Mode",
    description: "Hide desktop icons while you present or share your screen.",
});

async function hideDesktopIcons(hide) {
    await macotron.shell.run("/usr/bin/defaults", [
        "write", "com.apple.finder", "CreateDesktop", hide ? "false" : "true",
    ]);
    await macotron.shell.run("/usr/bin/killall", ["Finder"]);
}

// Finder's own setting outlives Macotron, so ask it rather than remembering:
// a plugin variable would come back false after a restart with the icons
// still hidden, and the next toggle would hide them again.
async function iconsHidden() {
    const r = await macotron.shell.run("/usr/bin/defaults", [
        "read", "com.apple.finder", "CreateDesktop",
    ]);
    // The key is absent until something writes it, and absent means shown.
    return String(r.stdout || "").trim() === "false";
}

macotron.command("Toggle Present Mode", "Hide desktop icons for screensharing", async () => {
    try {
        const presenting = !(await iconsHidden());
        await hideDesktopIcons(presenting);
        macotron.notify.toast("Present Mode", presenting ? "On — desktop icons hidden" : "Off", { color: "success" });
    } catch (err) {
        macotron.notify.toast("Present Mode", String(err), { color: "failure" });
    }
});
