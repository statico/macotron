macotron.plugin({
  title: "Pomodoro",
  description: "Menubar work timer.",
});

const WORK_MS = 25 * 60 * 1000;
const BREAK_MS = 5 * 60 * 1000;
let remaining = 0;
let running = false;
let phase = "idle";
let completed = 0;

function fmt(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function statusLine() {
    if (!running) return "Idle";
    return (phase === "work" ? "Work" : "Break") + " — " + fmt(remaining) + " left";
}

function menu() {
    const rows = [
        { title: statusLine() },
        { title: completed + (completed === 1 ? " pomodoro" : " pomodoros") + " this session" },
        { title: "Work 25:00  ·  Break 5:00" },
        "-",
    ];
    if (!running) {
        rows.push({ title: "Start Work", onClick: startWork });
        rows.push({ title: "Start Break", onClick: startBreak });
    } else {
        rows.push({
            title: phase === "work" ? "Skip to Break" : "Skip to Work",
            onClick: phase === "work" ? startBreak : startWork,
        });
        rows.push({ title: "Stop", onClick: stop });
    }
    return rows;
}

function paint() {
    macotron.menubar.status("pomodoro", {
        title: running ? fmt(remaining) : "",
        sfSymbol: "timer",
        color: phase === "work" ? "green" : phase === "break" ? "orange" : null,
        menu: menu(),
    });
}

function tick() {
    if (!running) return;
    remaining -= 1000;
    if (remaining <= 0) {
        if (phase === "work") {
            completed += 1;
            startBreak();
            macotron.notify.show("Pomodoro", "Break — 5 minutes", { sound: true });
            return;
        }
        stop();
        macotron.notify.show("Pomodoro", "Break over", { sound: true });
        return;
    }
    paint();
}

function startWork() {
    remaining = WORK_MS;
    running = true;
    phase = "work";
    paint();
}

function startBreak() {
    remaining = BREAK_MS;
    running = true;
    phase = "break";
    paint();
}

function stop() {
    running = false;
    remaining = 0;
    phase = "idle";
    paint();
}

paint();
macotron.every(1000, tick);

macotron.command("Start Pomodoro", "25-minute focus timer in the menubar", startWork);
