// demo-idle.js
// APIs: macotron.idle.seconds, macotron.idle.setThreshold, macotron.on("system:idle"), macotron.on("system:active"), macotron.notify, macotron.command

macotron.plugin({
  title: "Idle",
  description: "Notify when the Mac goes idle or wakes.",
});

let lastTransition = "none";

macotron.on("system:idle", () => {
    lastTransition = "idle";
});

macotron.on("system:active", () => {
    lastTransition = "active";
});

macotron.command("Idle Seconds", "Show seconds since last HID input", () => {
    const seconds = Math.floor(macotron.idle.seconds());
    macotron.notify.toast("Idle", `${seconds}s (last transition: ${lastTransition})`);
});
