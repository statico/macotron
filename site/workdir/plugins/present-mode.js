// APIs: command, shell.run, notify

macotron.plugin({
  title: "Present Mode",
  description: "Hide desktop icons while you present or share your screen.",
});

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
        macotron.notify.toast("Present Mode", presenting ? "On — desktop icons hidden" : "Off", { color: "success" });
    } catch (err) {
        macotron.notify.toast("Present Mode", String(err), { color: "failure" });
    }
});
