// APIs: command, shell.run, notify

let presenting = false;

async function hideDesktopIcons(hide) {
    await macotron.shell.run("/usr/bin/defaults", [
        "write", "com.apple.finder", "CreateDesktop", hide ? "false" : "true",
    ]);
    await macotron.shell.run("/usr/bin/killall", ["Finder"]);
}

async function setDoNotDisturb(on) {
    const focus = on ? "com.apple.donotdisturb.mode" : "";
    try {
        if (on) {
            await macotron.shell.run("/usr/bin/shortcuts", ["run", "Set Focus to Do Not Disturb"]);
        } else {
            await macotron.shell.run("/usr/bin/shortcuts", ["run", "Turn Off Focus"]);
        }
    } catch (_) {
        void focus;
    }
}

macotron.command("Toggle Present Mode", "Hide desktop icons for screensharing", async () => {
    presenting = !presenting;
    try {
        await hideDesktopIcons(presenting);
        await setDoNotDisturb(presenting);
        macotron.notify.show("Present Mode", presenting ? "On — desktop icons hidden" : "Off");
    } catch (err) {
        macotron.notify.show("Present Mode", String(err));
    }
});
