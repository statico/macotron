// APIs: fs.list, ocr.recognize, fs.rename, command, notify
macotron.plugin({
  title: "Screenshot Rename",
  description: "Rename the latest screenshot from the text in the image.",
  permissions: ["screenRecording"],
});

function slug(text) {
    const cut = text.split(/\n/)[0].replace(/[^\w\s-]/g, "").replace(/\s+/g, "-").replace(/-+/g, "-");
    return (cut.slice(0, 48).replace(/^-|-$/g, "") || "screenshot").toLowerCase();
}

function newestScreenshot() {
    const names = macotron.fs.list("~/Desktop").filter((name) =>
        /\.png$/i.test(name) && (/^Screenshot /i.test(name) || /^Screen Shot /i.test(name))
    );
    names.sort();
    return names.length ? names[names.length - 1] : null;
}

macotron.command("Rename Last Screenshot", "OCR the newest Desktop screenshot and rename it", async () => {
    const name = newestScreenshot();
    if (!name) {
        macotron.notify.toast("Screenshot rename", "No screenshots on the Desktop");
        return;
    }
    const src = "~/Desktop/" + name;
    try {
        const text = await macotron.ocr.recognize({ path: src });
        let destName = slug(text) + ".png";
        let dest = "~/Desktop/" + destName;
        let n = 2;
        while (macotron.fs.exists(dest) && dest !== src) {
            destName = slug(text) + "-" + n + ".png";
            dest = "~/Desktop/" + destName;
            n += 1;
        }
        if (dest !== src) macotron.fs.rename(src, dest);
        macotron.notify.toast("Screenshot renamed", destName, { color: "success" });
    } catch (err) {
        macotron.notify.toast("Screenshot rename failed", String(err), { color: "failure" });
    }
});
