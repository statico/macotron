// APIs: macotron.display.getBrightness, setBrightness, setXDREnabled, isXDREnabled

macotron.plugin({
    title: "Brightness Commands",
    description: "Dim or brighten the display, and turn XDR on or off.",
});

function nudgeBrightness(delta) {
    const current = macotron.display.getBrightness();
    if (current >= 0) macotron.display.setBrightness(current + delta);
}

macotron.keyboard.on("Dimmer", "ctrl+opt+-", () => nudgeBrightness(-0.1));
macotron.keyboard.on("Brighter", "ctrl+opt+=", () => nudgeBrightness(0.1));

macotron.command("Toggle XDR", "Toggle extended dynamic range headroom", () => {
    macotron.display.setXDREnabled(!macotron.display.isXDREnabled());
});
