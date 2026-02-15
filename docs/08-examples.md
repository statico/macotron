# Example Snippets

These are what the AI generates. Users describe what they want; these files appear on disk.

## Window Tiling (replaces Rectangle)

> User: "set up keyboard shortcuts to tile my windows"

```javascript
// ~/.macotron/snippets/001-window-tiling.js

macotron.keyboard.on("ctrl+opt+left", () => {
    const win = macotron.window.focused();
    if (win) macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 0.5, h: 1 });
});

macotron.keyboard.on("ctrl+opt+right", () => {
    const win = macotron.window.focused();
    if (win) macotron.window.moveToFraction(win.id, { x: 0.5, y: 0, w: 0.5, h: 1 });
});

macotron.keyboard.on("ctrl+opt+return", () => {
    const win = macotron.window.focused();
    if (win) macotron.window.moveToFraction(win.id, { x: 0, y: 0, w: 1, h: 1 });
});
```

## URL Router (replaces Velja)

> User: "open YouTube links in Safari, everything else in Arc"

```javascript
// ~/.macotron/snippets/002-url-handlers.js

macotron.url.registerHandler("https");

macotron.url.on("https", "youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.url.on("https", "*", (event) => {
    macotron.url.open(event.url, "company.thebrowser.Browser");
});
```

## Camera Ring Light (replaces OverSight)

> User: "turn on my ring light when my camera activates"

```javascript
// ~/.macotron/snippets/003-camera-light.js

macotron.on("camera:active", async () => {
    await macotron.http.post("http://192.168.1.50/api/on", {});
    macotron.notify.show("Ring light ON", "Camera detected");
});

macotron.on("camera:inactive", async () => {
    await macotron.http.post("http://192.168.1.50/api/off", {});
    macotron.notify.show("Ring light OFF", "Camera stopped");
});
```

## CPU Temperature Monitor

```javascript
// ~/.macotron/snippets/004-cpu-monitor.js

macotron.every(30_000, async () => {
    const temp = await macotron.system.cpuTemp();
    if (temp > 90) {
        macotron.notify.show("CPU Temperature Warning", `CPU is at ${temp}°C`);
    }
});
```

## Menubar Dashboard (replaces xbar)

```javascript
// ~/.macotron/snippets/005-menubar-dashboard.js

macotron.menubar.add("cpu-temp", {
    title: "CPU: --°C",
    icon: "thermometer",
    section: "System"
});

macotron.every(10_000, async () => {
    const temp = await macotron.system.cpuTemp();
    macotron.menubar.update("cpu-temp", {
        title: `CPU: ${Math.round(temp)}°C`,
        icon: temp > 80 ? "thermometer.sun.fill" : "thermometer"
    });
});
```

## Summarize Screen (launcher command)

```javascript
// ~/.macotron/commands/summarize-screen.js

macotron.command("Summarize Screen", "Take a screenshot and summarize with AI", async () => {
    const screenshot = await macotron.screen.capture();
    const ai = macotron.ai.claude();
    const summary = await ai.chat("Describe what's on this screen concisely.", { image: screenshot });
    macotron.notify.show("Screen Summary", summary);
});
```
