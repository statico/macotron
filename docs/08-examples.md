# Example Plugins

External agents write these files under `plugins/` in the workdir. Macotron loads them and hot-reloads on change.

| Goal | Plugin file |
|---|---|
| Window tiling shortcuts | `plugins/window-tiling.js` |
| Open YouTube in Safari | `plugins/url-handlers.js` |
| Ring light on camera | `plugins/camera-light.js` |
| CPU temperature warning | `plugins/cpu-monitor.js` |
| Menubar CPU widget | `plugins/menubar-dashboard.js` |
| Screen summary with AI | `plugins/summarize-screen.js` |
| Small panel UI | `plugins/hello-panel.js` |

---

## Window Tiling

```javascript
// plugins/window-tiling.js

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

## URL Router

```javascript
// plugins/url-handlers.js

macotron.url.registerHandler("https");

macotron.url.on("https", "youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.url.on("https", "*", (event) => {
    macotron.url.open(event.url, "company.thebrowser.Browser");
});
```

## Camera Ring Light

```javascript
// plugins/camera-light.js

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
// plugins/cpu-monitor.js

macotron.every(30_000, async () => {
    const temp = await macotron.system.cpuTemp();
    if (temp > 90) {
        macotron.notify.show("CPU Temperature Warning", `CPU is at ${temp}°C`);
    }
});
```

## Menubar Dashboard

```javascript
// plugins/menubar-dashboard.js

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

## Summarize Screen (plugin AI)

```javascript
// plugins/summarize-screen.js

macotron.keyboard.on("cmd+shift+s", async () => {
    const screenshot = await macotron.screen.capture();
    const ai = macotron.ai.claude();
    const summary = await ai.chat("Describe what is on this screen in a short form.", { image: screenshot });
    macotron.notify.show("Screen Summary", summary);
});
```

## Hello Panel

```javascript
// plugins/hello-panel.js

macotron.keyboard.on("cmd+shift+h", () => {
    const id = macotron.panel.open({
        title: "Hello",
        width: 420,
        height: 200,
        html: "<h1>Hello from Macotron</h1>"
    });
    macotron.panel.onMessage(id, (data) => {
        macotron.notify.show("Panel message", String(data));
    });
});
```
