// APIs: fs.list, fs.exists, image.convert, command, notify

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
    let ok = 0;
    let skipped = 0;
    const errors = [];
    for (const name of names) {
        const dest = "~/Downloads/" + name.replace(/\.hei[cf]$/i, ".jpg");
        if (macotron.fs.exists(dest)) {
            skipped += 1;
            continue;
        }
        const r = await macotron.image.convert("~/Downloads/" + name, dest, { quality: 1 });
        if (!r.ok) {
            errors.push(name + ": " + r.error);
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
