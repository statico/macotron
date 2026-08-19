// APIs: macotron.display.getBrightness, setBrightness, setXDREnabled, isXDREnabled

macotron.plugin({
  title: "Brightness",
  description: "Dim or brighten the display from the keyboard.",
});

function nudgeBrightness(delta) {
    const current = macotron.display.getBrightness();
    if (current >= 0) macotron.display.setBrightness(current + delta);
}

macotron.keyboard.on("dimmer", "ctrl+opt+-", () => nudgeBrightness(-0.1));
macotron.keyboard.on("brighter", "ctrl+opt+=", () => nudgeBrightness(0.1));

macotron.command("Toggle XDR", "Toggle extended dynamic range headroom", () => {
    macotron.display.setXDREnabled(!macotron.display.isXDREnabled());
});
