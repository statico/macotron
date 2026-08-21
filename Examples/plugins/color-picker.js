// APIs: screen.pickColor, clipboard.set, notify.toast, command
macotron.plugin({
  title: "Color Picker",
  description: "Click a pixel on screen and copy its color.",
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

macotron.keyboard.on("Pick Color", "cmd+shift+k", pickColor);
macotron.command("Pick Color", "Eyedropper: copy hex and show coordinates", pickColor);
