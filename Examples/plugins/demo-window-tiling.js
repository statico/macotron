// APIs: window.moveToFraction, keyboard, command
macotron.requirePermissions(["accessibility"]);

const tile = (frame) => {
  const window = macotron.window.focused();
  if (window) macotron.window.moveToFraction(window.id, frame);
};

macotron.keyboard.on("ctrl+opt+left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("ctrl+opt+right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.keyboard.on("ctrl+opt+up", () => tile({ x: 0, y: 0, w: 1, h: 0.5 }));
macotron.keyboard.on("ctrl+opt+down", () => tile({ x: 0, y: 0.5, w: 1, h: 0.5 }));

macotron.command("Tile Left Half", "Snap focused window left", () => tile({ x: 0, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Right Half", "Snap focused window right", () => tile({ x: 0.5, y: 0, w: 0.5, h: 1 }));
macotron.command("Tile Full Screen", "Maximize focused window", () => tile({ x: 0, y: 0, w: 1, h: 1 }));
