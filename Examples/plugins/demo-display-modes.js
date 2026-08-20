macotron.plugin({
    title: "Display Modes",
    description: "Toggle Night Shift, True Tone, and grayscale.",
});

function report(name, result) {
    if (!result || result.available === false || result.ok === false) {
        macotron.notify.toast(name, (result && result.error) || "Unavailable", { color: "failure" });
        return;
    }
    macotron.notify.toast(name, result.on ? "On" : "Off", { color: "success" });
}

macotron.command("Toggle Night Shift", "Enable or disable Night Shift", () => {
    const cur = macotron.display.nightShift();
    if (!cur.available) {
        macotron.notify.toast("Night Shift", "Unavailable", { color: "failure" });
        return;
    }
    report("Night Shift", macotron.display.setNightShift(!cur.on));
});

macotron.command("Night Shift 60%", "Set Night Shift strength to 0.6", () => {
    report("Night Shift", macotron.display.setNightShift({ strength: 0.6 }));
});

macotron.command("Toggle True Tone", "Enable or disable True Tone", () => {
    const cur = macotron.display.trueTone();
    if (!cur.available) {
        macotron.notify.toast("True Tone", "Unavailable", { color: "failure" });
        return;
    }
    report("True Tone", macotron.display.setTrueTone(!cur.on));
});

macotron.command("Toggle Grayscale", "Force the display to grayscale", () => {
    const cur = macotron.display.grayscale();
    if (!cur.available) {
        macotron.notify.toast("Grayscale", "Unavailable", { color: "failure" });
        return;
    }
    report("Grayscale", macotron.display.setGrayscale(!cur.on));
});
