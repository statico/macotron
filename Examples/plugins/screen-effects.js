macotron.plugin({
    title: "Screen Effects",
    description: "Control color, gamma, and system display effects.",
});

let nightVisionOn = false;

function toggleNightVision() {
    nightVisionOn = !nightVisionOn;
    if (nightVisionOn) {
        macotron.display.setGamma({ red: 1, green: 0, blue: 0 });
        macotron.notify.toast("Night vision", "On", { color: "success" });
    } else {
        macotron.display.restoreGamma();
        macotron.notify.toast("Night vision", "Off");
    }
}

const DIM = 0.35;
let gammaMode = "off";

function rgb(v) {
    return { red: v, green: v, blue: v };
}

function applyGamma() {
    if (gammaMode === "dim") {
        macotron.display.setGamma(rgb(DIM), rgb(0));
    } else if (gammaMode === "invert") {
        macotron.display.setGamma(rgb(0), rgb(1));
    } else {
        macotron.display.restoreGamma();
    }
}

function setGammaMode(next) {
    gammaMode = gammaMode === next ? "off" : next;
    applyGamma();
    const body = gammaMode === "dim" ? "Extra dark" : gammaMode === "invert" ? "Inverted" : "Off";
    macotron.notify.toast("Gamma", body, { color: gammaMode === "off" ? undefined : "success" });
}

function report(name, result) {
    if (!result || result.available === false || result.ok === false) {
        macotron.notify.toast(name, (result && result.error) || "Unavailable", { color: "failure" });
        return;
    }
    macotron.notify.toast(name, result.on ? "On" : "Off", { color: "success" });
}

macotron.command("Toggle Night Vision", "Tint the display red", toggleNightVision);
macotron.command("Toggle Extra Dark", "Dim below the hardware brightness floor", () => setGammaMode("dim"));
macotron.command("Toggle Invert Display", "Swap the gamma white and black points", () => setGammaMode("invert"));

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
