// APIs: command, prefs.get, prefs.set, shell.run, notify

macotron.plugin({
    title: "Presenter Mode",
    description: "Hide desktop icons while you present or share your screen.",
});

async function hideDesktopIcons(hide) {
    if (!macotron.prefs.set("com.apple.finder", "CreateDesktop", !hide)) {
        throw new Error("Couldn't write Finder's CreateDesktop setting");
    }
    await macotron.shell.run("/usr/bin/killall", ["Finder"]);
}

// Finder's own setting outlives Macotron, so ask it rather than remembering:
// a plugin variable would come back false after a restart with the icons
// still hidden, and the next toggle would hide them again.
function iconsHidden() {
    // The key is absent until something writes it, and absent means shown.
    // It is a boolean, or the string "false" if `defaults write` set it
    // without a type.
    const v = macotron.prefs.get("com.apple.finder", "CreateDesktop");
    return ["false", "0"].includes(String(v).toLowerCase());
}

macotron.command("Toggle Present Mode", "Hide desktop icons for screensharing", async () => {
    try {
        const presenting = !iconsHidden();
        await hideDesktopIcons(presenting);
        macotron.notify.toast("Present Mode", presenting ? "on — desktop icons hidden" : "off", { color: "success" });
    } catch (err) {
        macotron.notify.toast("Present Mode", String(err), { color: "failure" });
    }
});
