// demo-window-snap.js
// APIs: macotron.window.setSnapEnabled, macotron.window.isSnapEnabled, macotron.notify, macotron.command

macotron.requirePermissions(["accessibility"]);

macotron.window.setSnapEnabled(true);

macotron.command("Toggle Window Snap", "Enable or disable drag-to-edge snapping", () => {
    const next = !macotron.window.isSnapEnabled();
    const changed = macotron.window.setSnapEnabled(next);
    macotron.notify.show("Window Snap", changed ? (next ? "On" : "Off") : "Could not change snapping");
});
