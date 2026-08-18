// demo-idle.js
// APIs: macotron.idle.seconds, macotron.idle.setThreshold, macotron.on("system:idle"), macotron.on("system:active"), macotron.notify, macotron.command

let lastTransition = "none";

macotron.on("system:idle", () => {
    lastTransition = "idle";
});

macotron.on("system:active", () => {
    lastTransition = "active";
});

macotron.command("Idle seconds", "Show seconds since last HID input", () => {
    const seconds = Math.floor(macotron.idle.seconds());
    macotron.notify.show("Idle", `${seconds}s (last transition: ${lastTransition})`);
});
