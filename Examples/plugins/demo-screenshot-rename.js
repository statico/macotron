// APIs: fs.list, ocr.recognize, shell.run, command, notify
macotron.requirePermissions(["screenRecording"]);

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

async function homeDir() {
    const result = await macotron.shell.run("/usr/bin/printenv", ["HOME"]);
    return (result.stdout || "").trim();
}

macotron.command("Rename Last Screenshot", "OCR the newest Desktop screenshot and rename it", async () => {
    const name = newestScreenshot();
    if (!name) {
        macotron.notify.show("Screenshot rename", "No screenshots on the Desktop");
        return;
    }
    const src = "~/Desktop/" + name;
    try {
        const text = await macotron.ocr.recognize({ path: src });
        const home = await homeDir();
        let destName = slug(text) + ".png";
        let dest = "~/Desktop/" + destName;
        let n = 2;
        while (macotron.fs.exists(dest) && dest !== src) {
            destName = slug(text) + "-" + n + ".png";
            dest = "~/Desktop/" + destName;
            n += 1;
        }
        if (dest !== src) {
            await macotron.shell.run("/bin/mv", [home + "/Desktop/" + name, home + "/Desktop/" + destName]);
        }
        macotron.notify.show("Screenshot renamed", destName);
    } catch (err) {
        macotron.notify.show("Screenshot rename failed", String(err));
    }
});
