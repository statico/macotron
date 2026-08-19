// demo-window-snap.js
// APIs: macotron.window.snap, macotron.window.isSnapEnabled, macotron.window.setSnapEnabled, macotron.module, macotron.notify, macotron.command
// Drag a window to a screen edge or corner to tile it. Zones are {x,y,w,h} fractions of the visible frame.

macotron.requirePermissions(["accessibility"]);

const opts = macotron.module({
    title: "Window Snap",
    description: "Rectangle-style edge and quadrant snap. Edit zones in this plugin.",
    options: {
        threshold: { type: "number", label: "Edge threshold (px)", default: 20 },
        corner: { type: "number", label: "Corner size (px)", default: 48 },
        gap: { type: "number", label: "Gap (px)", default: 0 },
    },
});

macotron.window.snap({
    enabled: true,
    threshold: opts.threshold,
    corner: opts.corner,
    gap: opts.gap,
    zones: {
        left: { x: 0, y: 0, w: 0.5, h: 1 },
        right: { x: 0.5, y: 0, w: 0.5, h: 1 },
        top: { x: 0, y: 0, w: 1, h: 1 },
        bottom: { x: 0, y: 0.5, w: 1, h: 0.5 },
        tl: { x: 0, y: 0, w: 0.5, h: 0.5 },
        tr: { x: 0.5, y: 0, w: 0.5, h: 0.5 },
        bl: { x: 0, y: 0.5, w: 0.5, h: 0.5 },
        br: { x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
    },
});

macotron.command("Toggle Window Snap", "Enable or disable drag-to-edge snapping", () => {
    const next = !macotron.window.isSnapEnabled();
    const changed = macotron.window.setSnapEnabled(next);
    macotron.notify.show("Window Snap", changed ? (next ? "On" : "Off") : "Could not change snapping");
});
