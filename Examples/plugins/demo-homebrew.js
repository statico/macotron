// APIs: command, shell.run, clipboard.set, notify, panel

async function brew(args) {
    return macotron.shell.run("/opt/homebrew/bin/brew", args).catch(() =>
        macotron.shell.run("/usr/local/bin/brew", args)
    );
}

macotron.command("Brew List", "Show installed Homebrew formulae", async () => {
    try {
        const result = await brew(["list", "--formula"]);
        const names = (result.stdout || "").trim().split(/\s+/).filter(Boolean);
        const rows = names.map((name) =>
            `<div style="padding:4px 0;font:13px ui-monospace,monospace">${name.replace(/[<>&]/g, "")}</div>`
        ).join("");
        macotron.panel.open({
            title: "Homebrew",
            width: 360,
            height: 480,
            html: `<!DOCTYPE html><html><body style="margin:12px;font:13px system-ui">
<h3 style="margin:0 0 8px">Installed formulae (${names.length})</h3>
${rows || "<p>None</p>"}
</body></html>`,
        });
    } catch (err) {
        macotron.notify.show("Homebrew", String(err));
    }
});

macotron.command("Brew Copy Outdated", "Copy outdated formulae to the clipboard", async () => {
    try {
        const result = await brew(["outdated", "--formula"]);
        const text = (result.stdout || "").trim() || "All formulae are up to date";
        macotron.clipboard.set(text);
        macotron.notify.show("Homebrew", text.split("\n")[0]);
    } catch (err) {
        macotron.notify.show("Homebrew", String(err));
    }
});
