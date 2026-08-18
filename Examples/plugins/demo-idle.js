// demo-idle.js
// APIs: macotron.idle.seconds, macotron.idle.setThreshold, macotron.on("system:idle"), macotron.on("system:active"), macotron.notify, macotron.command

macotron.on("system:idle", () => {
    macotron.notify.show("Idle", "System is idle");
});

macotron.on("system:active", () => {
    macotron.notify.show("Active", "Input resumed");
});

macotron.command("Idle seconds", "Show seconds since last HID input", () => {
    macotron.notify.show("Idle", `${Math.floor(macotron.idle.seconds())}s`);
});
