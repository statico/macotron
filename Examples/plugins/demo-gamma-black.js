macotron.plugin({
    title: "Gamma Black",
    description: "Dim below hardware brightness, or invert the screen, with the gamma LUT.",
});

const DIM = 0.35;
let mode = "off";

function rgb(v) {
    return { red: v, green: v, blue: v };
}

function apply() {
    if (mode === "dim") {
        macotron.display.setGamma(rgb(DIM), rgb(0));
    } else if (mode === "invert") {
        macotron.display.setGamma(rgb(0), rgb(1));
    } else {
        macotron.display.restoreGamma();
    }
}

function setMode(next) {
    mode = mode === next ? "off" : next;
    apply();
    const body = mode === "dim" ? "Extra dark" : mode === "invert" ? "Inverted" : "Off";
    macotron.notify.toast("Gamma", body, { color: mode === "off" ? undefined : "success" });
}

macotron.command("Toggle Extra Dark", "Dim below the hardware brightness floor", () => setMode("dim"));
macotron.command("Toggle Invert Display", "Swap the gamma white and black points", () => setMode("invert"));
