// APIs: macotron.menubar.status, macotron.every, macotron.notify, macotron.command

const WORK_MS = 25 * 60 * 1000;
let remaining = 0;
let running = false;

function paint() {
    macotron.menubar.status("pomodoro", {
        title: running ? fmt(remaining) : "Pomodoro",
        sfSymbol: remaining <= 0 && !running ? "checkmark.circle" : "timer",
        color: running ? "orange" : null,
        bold: running,
        menu: [
            { title: "Start", onClick: start },
            { title: "Stop", onClick: stop },
        ],
    });
}

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
        paint();
        macotron.notify.show("Pomodoro", "25 minutes — take a break", { sound: true });
        return;
    }
    paint();
}

function start() {
    remaining = WORK_MS;
    running = true;
    paint();
    macotron.notify.show("Pomodoro", "25:00 started");
}

function stop() {
    running = false;
    remaining = 0;
    paint();
}

paint();
macotron.every(1000, tick);

macotron.command("Start Pomodoro", "25-minute focus timer in the menubar", start);
