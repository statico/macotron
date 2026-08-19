// APIs: fs.list, fs.exists, shell.run, command, notify

macotron.plugin({
  title: "Batch Rename",
  description: "Prefix today's Downloads files with the date.",
});

macotron.command("Prefix Downloads Today", "Prefix today's Downloads files with YYYY-MM-DD", async () => {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, "0");
    const d = String(now.getDate()).padStart(2, "0");
    const prefix = `${y}-${m}-${d}-`;
    const home = ((await macotron.shell.run("/usr/bin/printenv", ["HOME"])).stdout || "").trim();
    const names = macotron.fs.list("~/Downloads");
    let count = 0;
    for (const name of names) {
        if (name.startsWith(".") || name.startsWith(prefix)) continue;
        const destName = prefix + name;
        if (macotron.fs.exists("~/Downloads/" + destName)) continue;
        await macotron.shell.run("/bin/mv", [home + "/Downloads/" + name, home + "/Downloads/" + destName]);
        count += 1;
    }
    macotron.notify.toast("Batch rename", "Prefixed " + count + " files in Downloads", { color: "success" });
});
