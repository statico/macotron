macotron.plugin({
    title: "Layouts",
    description: "Save the current window layout and restore it later.",
    permissions: ["accessibility"],
});

const KEY = "layout:work";

function entriesFromWindows() {
    return macotron.window.getAll().map((win) => ({
        app: win.app,
        bundleID: win.bundleID,
        title: win.title,
        frame: win.frame,
        display: win.display,
    }));
}

macotron.command("Save Work", "Save the current window layout as Work", () => {
    const entries = entriesFromWindows();
    localStorage.setItem(KEY, JSON.stringify(entries));
    macotron.notify.toast("Layouts", "Saved " + entries.length + " windows", { color: "success" });
});

macotron.command("Restore Work", "Restore the saved Work layout", () => {
    const raw = localStorage.getItem(KEY);
    if (!raw) {
        macotron.notify.toast("Layouts", "No saved Work layout", { color: "warning" });
        return;
    }
    let entries;
    try {
        entries = JSON.parse(raw);
    } catch (_) {
        macotron.notify.toast("Layouts", "Saved layout is invalid", { color: "failure" });
        return;
    }
    const result = macotron.window.restore(entries);
    macotron.notify.toast(
        "Layouts",
        "Restored " + result.restored + ", missing " + result.missing,
        { color: result.missing ? "warning" : "success" }
    );
});
