// APIs: macotron.power, macotron.menubar, macotron.notify.show, macotron.command

macotron.plugin({
  title: "Stay Awake",
  description: "Keep this Mac awake from the menu bar.",
});

const DURATIONS = [
    { ms: 30 * 60 * 1000, label: "30 minutes" },
    { ms: 60 * 60 * 1000, label: "1 hour" },
    { ms: 2 * 60 * 60 * 1000, label: "2 hours" },
    { ms: 4 * 60 * 60 * 1000, label: "4 hours" },
];
const DEFAULT_MS = 4 * 60 * 60 * 1000;

let chosen = DEFAULT_MS;
let until = 0;

function fmt(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    if (h) return h + ":" + String(m).padStart(2, "0") + ":" + String(sec).padStart(2, "0");
    return m + ":" + String(sec).padStart(2, "0");
}

function left() {
    return Math.max(0, until - Date.now());
}

function labelFor(ms) {
    const d = DURATIONS.find((row) => row.ms === ms);
    return d ? d.label : fmt(ms);
}

function menu() {
    const on = macotron.power.isPreventing();
    const rows = [
        { title: on ? "Staying awake — " + fmt(left()) + " left" : "Sleep allowed" },
        "-",
    ];
    for (const d of DURATIONS) {
        rows.push({
            title: (on && chosen === d.ms ? "✓ " : "") + d.label,
            onClick: () => start(d.ms),
        });
    }
    rows.push("-");
    rows.push({ title: "Allow Sleep", onClick: stop });
    return rows;
}

function paint() {
    const on = macotron.power.isPreventing();
    macotron.menubar.status("power", {
        title: "",
        sfSymbol: on ? "cup.and.saucer.fill" : "cup.and.saucer",
        onClick: toggle,
        menu: menu(),
    });
}

function start(ms) {
    chosen = ms;
    until = Date.now() + ms;
    macotron.power.preventSleep({ reason: "Macotron keep awake" });
    macotron.notify.show("Stay Awake", "Awake for " + labelFor(ms), { sound: true });
    paint();
}

function stop() {
    until = 0;
    if (macotron.power.isPreventing()) {
        macotron.power.allowSleep();
        macotron.notify.show("Stay Awake", "Sleep allowed", { sound: true });
    }
    paint();
}

function toggle() {
    if (macotron.power.isPreventing()) stop();
    else start(chosen);
}

function tick() {
    if (!macotron.power.isPreventing()) return;
    if (left() <= 0) {
        stop();
        return;
    }
    paint();
}

paint();
macotron.every(1000, tick);

macotron.command("Toggle Keep Awake", "Prevent sleep for 4 hours", toggle);
