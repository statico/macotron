macotron.plugin({
    title: "Pomodoro Timer",
    description: "Run a 25-minute focus timer in the menu bar.",
});

const WORK_MS = 25 * 60 * 1000;
const BREAK_MS = 5 * 60 * 1000;
const KEY = "pomodoro.session";

// A deadline, not a countdown: an edit reloads every plugin and a restart
// clears the lot, and neither should cost the user the timer they started.
let endsAt = 0;
let phase = "idle";
let completed = 0;

function running() {
    return phase !== "idle";
}

function remainingMs() {
    return Math.max(0, endsAt - Date.now());
}

function save() {
    localStorage.setItem(KEY, JSON.stringify({ endsAt, phase, completed }));
}

function fmt(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function statusLine() {
    if (!running()) return "Idle";
    return (phase === "work" ? "Work" : "Break") + " — " + fmt(remainingMs()) + " left";
}

function menu() {
    const rows = [
        { title: statusLine() },
        { title: completed + (completed === 1 ? " pomodoro" : " pomodoros") + " this session" },
        { title: "Work 25:00  ·  Break 5:00" },
        "-",
    ];
    if (!running()) {
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
        title: running() ? fmt(remainingMs()) : "",
        sfSymbol: "timer",
        color: phase === "work" ? "green" : phase === "break" ? "orange" : null,
        // Menu bar fonts are proportional, so "11:11" is narrower than "00:00"
        // and neighbors would shift every second. minWidth is in points; 72
        // covers the timer icon plus the widest MM:SS this plugin shows ("25:00").
        minWidth: running() ? 72 : undefined,
        menu: menu(),
    });
}

function tick() {
    if (!running()) return;
    if (remainingMs() <= 0) {
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
    endsAt = Date.now() + WORK_MS;
    phase = "work";
    save();
    paint();
}

function startBreak() {
    endsAt = Date.now() + BREAK_MS;
    phase = "break";
    save();
    paint();
}

function stop() {
    endsAt = 0;
    phase = "idle";
    save();
    paint();
}

const saved = JSON.parse(localStorage.getItem(KEY) || "null");
if (saved) {
    completed = saved.completed || 0;
    // A timer that ran out while the app was away is simply over.
    if (saved.endsAt > Date.now()) {
        endsAt = saved.endsAt;
        phase = saved.phase;
    }
}

paint();
macotron.every(1000, tick);

macotron.command("Start Pomodoro", "25-minute focus timer in the menu bar", startWork);
