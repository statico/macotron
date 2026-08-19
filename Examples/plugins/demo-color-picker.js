// APIs: screen.pickColor, clipboard.set, notify.toast, command
macotron.plugin({
  title: "Color Picker",
  description: "Pick a screen color with the system magnifier.",
});

async function pickColor() {
    macotron.notify.toast("Click a pixel to pick its color", { duration: 4000 });
    const color = await macotron.screen.pickColor();
    if (!color) return;
    macotron.clipboard.set(color.hex);
    macotron.notify.toast(color.hex, `${color.x}, ${color.y}`, {
        sfSymbol: "circle.fill",
        color: color.hex,
    });
}

macotron.keyboard.on("pick-color", "cmd+shift+k", pickColor);
macotron.command("Pick Color", "Eyedropper: copy hex and show coordinates", pickColor);
