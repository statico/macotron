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
            `<div class="mono">${name.replace(/[<>&]/g, "")}</div>`
        ).join("");
        macotron.panel.open({
            title: "Homebrew",
            width: 360,
            height: 480,
            html: `<h3>Installed formulae (${names.length})</h3>
<div class="grow scroll">${rows || '<p class="muted">None</p>'}</div>`,
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
