// APIs: fs.list, fs.exists, shell.run, command, notify

macotron.plugin({
  title: "HEIC to JPEG",
  description: "Convert HEIC photos in Downloads to JPEG.",
});

macotron.command("Convert Downloads HEIC", "Write JPEGs next to HEIC files in Downloads", async () => {
    const names = macotron.fs.list("~/Downloads").filter((name) => /\.hei[cf]$/i.test(name));
    if (!names.length) {
        macotron.notify.toast("HEIC to JPEG", "No HEIC files in Downloads");
        return;
    }
    const home = (await macotron.shell.run("/usr/bin/printenv", ["HOME"])).stdout.trim();
    const dir = home + "/Downloads";
    let ok = 0;
    let skipped = 0;
    const errors = [];
    for (const name of names) {
        const destName = name.replace(/\.hei[cf]$/i, ".jpg");
        const destRel = "~/Downloads/" + destName;
        if (macotron.fs.exists(destRel)) {
            skipped += 1;
            continue;
        }
        const r = await macotron.shell.run("/usr/bin/sips", [
            "-s", "format", "jpeg",
            "-s", "formatOptions", "100",
            dir + "/" + name,
            "--out", dir + "/" + destName,
        ]);
        if (r.exitCode !== 0) {
            errors.push(name + ": " + String(r.stderr || r.stdout).trim());
            continue;
        }
        ok += 1;
    }
    const parts = [ok + " converted"];
    if (skipped) parts.push(skipped + " already existed");
    if (errors.length) parts.push(errors.length + " failed");
    macotron.notify.toast("HEIC to JPEG", parts.join(", "), {
        color: errors.length ? "warning" : "success",
    });
    if (errors.length) macotron.log(errors.join("\n"));
});
