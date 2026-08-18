// demo-keep-awake.js
// APIs: macotron.menubar, macotron.shell, macotron.notify, macotron.command
// Until PowerModule lands: keep awake via `caffeinate -dims`.

let awake = false;
let caffeinatePid = null;

async function startCaffeinate() {
    // Launch in background; remember pid via shell.
    const result = await macotron.shell.run("bash", [
        "-lc",
        'caffeinate -dims >/dev/null 2>&1 & echo $!',
    ]);
    const pid = parseInt((result.stdout || "").trim(), 10);
    if (!pid || result.exitCode !== 0) {
        throw new Error(result.stderr || "failed to start caffeinate");
    }
    caffeinatePid = pid;
    awake = true;
}

async function stopCaffeinate() {
    if (caffeinatePid) {
        await macotron.shell.run("kill", [String(caffeinatePid)]);
        caffeinatePid = null;
    } else {
        await macotron.shell.run("pkill", ["-x", "caffeinate"]);
    }
    awake = false;
}

function refreshMenubar() {
    macotron.menubar.update("keep-awake", {
        title: awake ? "Awake ON" : "Awake OFF",
        icon: awake ? "cup.and.saucer.fill" : "cup.and.saucer",
    });
}

async function toggle() {
    try {
        if (awake) {
            await stopCaffeinate();
            macotron.notify.show("Keep Awake", "Sleep allowed again");
        } else {
            await startCaffeinate();
            macotron.notify.show("Keep Awake", "System will stay awake");
        }
        refreshMenubar();
    } catch (err) {
        macotron.notify.show("Keep Awake", String(err));
    }
}

macotron.menubar.add("keep-awake", {
    title: "Awake OFF",
    icon: "cup.and.saucer",
    section: "System",
    onClick: () => {
        toggle();
    },
});

macotron.command("Toggle Keep Awake", "Run or stop caffeinate -dims", () => {
    toggle();
});
