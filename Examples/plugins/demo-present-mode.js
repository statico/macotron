// APIs: command, shell.run, notify

let presenting = false;

async function hideDesktopIcons(hide) {
    await macotron.shell.run("/usr/bin/defaults", [
        "write", "com.apple.finder", "CreateDesktop", hide ? "false" : "true",
    ]);
    await macotron.shell.run("/usr/bin/killall", ["Finder"]);
}

macotron.command("Toggle Present Mode", "Hide desktop icons for screensharing", async () => {
    presenting = !presenting;
    try {
        await hideDesktopIcons(presenting);
        macotron.notify.show("Present Mode", presenting ? "On — desktop icons hidden" : "Off");
    } catch (err) {
        macotron.notify.show("Present Mode", String(err));
    }
});
