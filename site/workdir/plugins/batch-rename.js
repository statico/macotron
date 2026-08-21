// APIs: fs.list, fs.exists, fs.rename, command, notify

macotron.plugin({
  title: "Batch Rename",
  description: "Add today's date to the start of files you downloaded today.",
});

macotron.command("Prefix Downloads Today", "Prefix today's Downloads files with YYYY-MM-DD", () => {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, "0");
    const d = String(now.getDate()).padStart(2, "0");
    const prefix = `${y}-${m}-${d}-`;
    const names = macotron.fs.list("~/Downloads");
    let count = 0;
    for (const name of names) {
        if (name.startsWith(".") || name.startsWith(prefix)) continue;
        const destName = prefix + name;
        if (macotron.fs.exists("~/Downloads/" + destName)) continue;
        macotron.fs.rename("~/Downloads/" + name, "~/Downloads/" + destName);
        count += 1;
    }
    macotron.notify.toast("Batch rename", "Prefixed " + count + " files in Downloads", { color: "success" });
});
