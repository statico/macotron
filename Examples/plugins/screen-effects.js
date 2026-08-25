macotron.plugin({
    title: "Screen Effects",
    description: "Tint, dim, invert, or add a CRT overlay to the display. Toggle Night Shift, True Tone, and grayscale.",
    help: "Use the launcher commands to tint the display red, dim it below the usual brightness limit, invert colors, or overlay a CRT look. You can also turn Night Shift, True Tone, and grayscale on or off.\n\nThe CRT overlay sits on top of the desktop. It adds scanlines and darkens the picture; it does not curve the image. Turn the overlay off and on again after you connect a display so the new screen is covered.",
});

const DIM = 0.35;
const KEY = "screen-effects.gamma";

// The host hands the gamma table back to macOS whenever plugins reload, so a
// dimmed or red screen would quietly go back to normal on an unrelated edit.
// Remember the mode and put it back on.
let gammaMode = localStorage.getItem(KEY) || "off";

function rgb(v) {
    return { red: v, green: v, blue: v };
}

function applyGamma() {
    if (gammaMode === "night-vision") {
        macotron.display.setGamma({ red: 1, green: 0, blue: 0 });
    } else if (gammaMode === "dim") {
        macotron.display.setGamma(rgb(DIM), rgb(0));
    } else if (gammaMode === "invert") {
        macotron.display.setGamma(rgb(0), rgb(1));
    } else {
        macotron.display.restoreGamma();
    }
}

function toggleGammaMode(mode) {
    const active = gammaMode === mode;
    gammaMode = active ? "off" : mode;
    localStorage.setItem(KEY, gammaMode);
    applyGamma();
    if (mode === "night-vision") {
        macotron.notify.toast("Night vision", active ? "Off" : "On", { color: active ? undefined : "success" });
    } else {
        const body = active ? "Off" : mode === "dim" ? "Extra dark" : "Inverted";
        macotron.notify.toast("Gamma", body, { color: active ? undefined : "success" });
    }
}

function report(name, result) {
    if (!result || result.available === false || result.ok === false) {
        macotron.notify.toast(name, (result && result.error) || "Unavailable", { color: "failure" });
        return;
    }
    macotron.notify.toast(name, result.on ? "On" : "Off", { color: "success" });
}

macotron.command("Toggle Night Vision", "Tint the display red", () => toggleGammaMode("night-vision"));
macotron.command("Toggle Extra Dark", "Dim below the hardware brightness floor", () => toggleGammaMode("dim"));
macotron.command("Toggle Invert Display", "Swap the gamma white and black points", () => toggleGammaMode("invert"));

macotron.command("Toggle CRT Effect", "Overlay scanlines and a phosphor grille", () => {
    const on = macotron.display.isCRTEnabled();
    if (!macotron.display.setCRTEnabled(!on)) {
        macotron.notify.toast("CRT effect", "Unavailable", { color: "failure" });
        return;
    }
    macotron.notify.toast("CRT effect", on ? "Off" : "On", { color: on ? undefined : "success" });
});

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

if (gammaMode !== "off") applyGamma();
