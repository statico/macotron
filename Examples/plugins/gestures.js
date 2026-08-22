macotron.plugin({
  title: "Gesture Examples",
  description: "Swipe three fingers left or right to tile the focused window.",
  permissions: ["inputMonitoring", "accessibility"],
});

macotron.event.tap("swipe", (e) => {
  if (e.fingers !== 3) return;
  const win = macotron.window.focused();
  if (!win) return;
  if (e.direction === "left") {
    macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 0.5, h: 1 });
  } else if (e.direction === "right") {
    macotron.window.moveToFraction(win.id, { x: 0.5, y: 0, w: 0.5, h: 1 });
  }
});
