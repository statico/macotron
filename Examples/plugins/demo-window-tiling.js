// APIs: window.moveToFraction, keyboard, command
macotron.requirePermissions(["accessibility"]);

const tile = (frame) => {
  const window = macotron.window.focused();
  if (window) macotron.window.moveToFraction(window.id, frame);
};

macotron.keyboard.on("tile-left", "ctrl+opt+left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("tile-right", "ctrl+opt+right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("tile-up", "ctrl+opt+up", () => tile({ x: 0, y: 0, w: 1, h: 0.5 }));
macotron.keyboard.on("tile-down", "ctrl+opt+down", () => tile({ x: 0, y: 0.5, w: 1, h: 0.5 }));

function neighborDisplay(current, delta) {
    const displays = macotron.display.list();
    if (displays.length < 2) return undefined;
    const i = displays.findIndex((d) => d.id === current);
    return displays[(Math.max(i, 0) + delta + displays.length) % displays.length].id;
}

macotron.keyboard.on("tile-next-display", "ctrl+opt+cmd+right", () => {
    const window = macotron.window.focused();
    if (window) macotron.window.moveToFraction(window.id, { x: 0, y: 0, w: 1, h: 1, display: neighborDisplay(window.display, 1) });
});
macotron.keyboard.on("tile-prev-display", "ctrl+opt+cmd+left", () => {
    const window = macotron.window.focused();
    if (window) macotron.window.moveToFraction(window.id, { x: 0, y: 0, w: 1, h: 1, display: neighborDisplay(window.display, -1) });
});

macotron.command("Tile Left Half", "Snap focused window left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Right Half", "Snap focused window right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Full Screen", "Maximize focused window", () => tile({ x: 0, y: 0, w: 1, h: 1 }));
