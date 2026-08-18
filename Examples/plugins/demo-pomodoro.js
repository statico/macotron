// demo-pomodoro.js
// APIs: macotron.menubar, macotron.every, macotron.notify, macotron.command

const WORK_MS = 25 * 60 * 1000;
let remaining = 0;
let running = false;

macotron.menubar.add("pomodoro", {
    title: "Pomodoro",
    icon: "timer",
    section: "Focus",
    onClick: start,
});

function fmt(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function tick() {
    if (!running) return;
    remaining -= 1000;
    if (remaining <= 0) {
        running = false;
        remaining = 0;
        macotron.menubar.update("pomodoro", { title: "Done!", icon: "checkmark.circle" });
        macotron.notify.show("Pomodoro", "25 minutes — take a break", { sound: true });
        return;
    }
    macotron.menubar.update("pomodoro", { title: fmt(remaining), icon: "timer" });
}

function start() {
    remaining = WORK_MS;
    running = true;
    macotron.menubar.update("pomodoro", { title: fmt(remaining), icon: "timer" });
    macotron.notify.show("Pomodoro", "25:00 started");
}

macotron.every(1000, tick);

macotron.command("Start Pomodoro", "25-minute focus timer in the menubar", start);
