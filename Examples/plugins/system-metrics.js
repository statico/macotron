const opts = macotron.plugin({
    title: "System Metrics Example",
    description: "Show CPU and GPU usage in the menu bar.",
    options: {
        colorize: {
            type: "boolean",
            label: "Colorize by load",
            help: "Turns the numbers green, orange, then red as usage climbs.",
            default: true,
        },
        cpuAlert: {
            type: "boolean",
            label: "Alert on sustained high CPU",
            help: "Notifies when the CPU stays above the threshold. Brief spikes are ignored.",
            default: false,
        },
        cpuThreshold: {
            type: "number",
            label: "CPU threshold (%)",
            default: 85,
            min: 10,
            max: 100,
        },
        cpuSamples: {
            type: "number",
            label: "CPU samples before alerting",
            help: "Samples are two seconds apart, so 5 means the CPU has to stay high for ten seconds.",
            default: 5,
            min: 1,
            max: 60,
        },
        diskAlert: {
            type: "boolean",
            label: "Alert on low disk space",
            default: false,
        },
        diskFreeGB: {
            type: "number",
            label: "Free disk threshold (GB)",
            default: 10,
            min: 1,
            max: 500,
        },
        batteryAlert: {
            type: "boolean",
            label: "Alert on low battery",
            help: "Only while running on battery — charging back up through the threshold is not news.",
            default: false,
        },
        batteryThreshold: {
            type: "number",
            label: "Battery threshold (%)",
            default: 20,
            min: 5,
            max: 90,
        },
        memoryAlert: {
            type: "boolean",
            label: "Alert on memory pressure",
            help: "Fires when macOS reports warning or critical memory pressure.",
            default: false,
        },
    },
});

const GREEN = "#34C759";
const ORANGE = "#FF9500";
const RED = "#FF3B30";

function tint(n) {
    if (n >= 80) return RED;
    if (n >= 50) return ORANGE;
    return GREEN;
}

function snapshot() {
    const cpu = Math.round(macotron.system.cpu().usage);
    const gpu = macotron.system.gpu();
    const gpuN = Math.round(gpu && gpu.usage != null ? gpu.usage : 0);
    const mem = macotron.system.memory();
    const usedGB = (mem.used / (1024 * 1024 * 1024)).toFixed(1);
    const totalGB = (mem.total / (1024 * 1024 * 1024)).toFixed(0);
    const bat = macotron.system.battery();
    const disk = macotron.system.disk();
    const diskUsed = disk.total ? Math.round((disk.used / disk.total) * 100) : 0;
    const freeGB = disk.total ? (disk.total - disk.used) / (1024 * 1024 * 1024) : 0;
    // memory().pressure is newer than this plugin, so a host that predates it
    // reports undefined. Undefined means "nothing told us anything is wrong",
    // which is normal — not critical.
    const pressure = mem.pressure || "normal";
    return { cpu, gpuN, gpuName: gpu && gpu.name, usedGB, totalGB, bat, diskUsed, freeGB, pressure };
}

// Alerts latch. A breached threshold notifies once and then stays quiet until
// the value recovers — without that, a full disk would notify every two
// seconds forever, and the user would turn the plugin off rather than empty
// the disk.
const ALERT_KEY = "alert-state";
// A value parked right on its threshold (battery reading 20, 21, 20) would
// otherwise clear and re-trigger on alternate samples and notify the whole way
// down, so a recovered alert also has to wait this long before it can fire.
const COOLDOWN_MS = 30 * 60 * 1000;

// Pure, so the decision can be tested without a two-second clock: given the
// stored state for one alert and whether this sample breaches, say whether to
// notify now. `needed` consecutive breaching samples are required, which is
// what keeps a momentary CPU spike from alerting.
function alertStep(state, breached, now, needed) {
    const prev = state || {};
    // null, not 0: an alert that has never fired has no cooldown to serve,
    // and defaulting to 0 would make "never fired" look like "fired at the
    // epoch" — which only happens to behave because Date.now() is large.
    const firedAt = typeof prev.firedAt === "number" ? prev.firedAt : null;
    // Recovery re-arms the alert but does not reset the cooldown: the next
    // breach is still a new notification, just not an immediate one.
    if (!breached) return { streak: 0, latched: false, firedAt: firedAt, notify: false };
    const streak = (prev.streak || 0) + 1;
    const cooling = firedAt !== null && now - firedAt < COOLDOWN_MS;
    if (prev.latched === true || streak < (needed || 1) || cooling) {
        return { streak: streak, latched: prev.latched === true, firedAt: firedAt, notify: false };
    }
    return { streak: streak, latched: true, firedAt: now, notify: true };
}

function num(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

// The latches outlive the plugin: reloading Macotron with the disk still full
// should not re-announce it.
function loadAlerts() {
    try {
        return JSON.parse(localStorage.getItem(ALERT_KEY) || "{}");
    } catch (err) {
        return {};
    }
}

function checkAlerts(s) {
    const state = loadAlerts();
    const now = Date.now();
    const bat = s.bat;
    const checks = [
        ["cpu", opts.cpuAlert, s.cpu >= num(opts.cpuThreshold, 85), num(opts.cpuSamples, 5),
            "High CPU", "CPU has held at " + s.cpu + "% for the last " + num(opts.cpuSamples, 5) + " samples."],
        ["disk", opts.diskAlert, s.freeGB <= num(opts.diskFreeGB, 10), 1,
            "Low disk space", s.freeGB.toFixed(1) + " GB free on the startup disk."],
        // Charging through the threshold is not news, so only complain while
        // the battery is actually draining.
        ["battery", opts.batteryAlert,
            !!bat && bat.level >= 0 && !bat.charging && bat.level <= num(opts.batteryThreshold, 20), 1,
            "Low battery", bat ? Math.round(bat.level) + "% remaining." : ""],
        ["memory", opts.memoryAlert, s.pressure === "warning" || s.pressure === "critical", 1,
            "Memory pressure", "The system reports " + s.pressure + " memory pressure."],
    ];

    for (const [key, enabled, breached, needed, title, body] of checks) {
        // Turning an alert off forgets its latch, so turning it back on later
        // reports the condition instead of sitting silently latched.
        if (!enabled) {
            delete state[key];
            continue;
        }
        const next = alertStep(state[key], breached, now, needed);
        if (next.notify) macotron.notify.show(title, body, { sound: true });
        state[key] = { streak: next.streak, latched: next.latched, firedAt: next.firedAt };
    }

    localStorage.setItem(ALERT_KEY, JSON.stringify(state));
}

function menu(s) {
    const rows = [
        { title: "CPU " + s.cpu + "%" },
        { title: "GPU " + s.gpuN + "%" + (s.gpuName ? " — " + s.gpuName : "") },
        { title: "Memory " + s.usedGB + "/" + s.totalGB + " GB" },
        { title: "Disk " + s.diskUsed + "% used" },
    ];
    if (s.bat && s.bat.level >= 0) {
        let extra = s.bat.charging ? " charging" : "";
        if (s.bat.charging && s.bat.timeToFull > 0) extra += " · " + s.bat.timeToFull + " min";
        if (!s.bat.charging && s.bat.timeRemaining > 0) extra = " · " + s.bat.timeRemaining + " min";
        rows.push({ title: "Battery " + Math.round(s.bat.level) + "%" + extra });
    }
    rows.push("-", { title: "Settings…", onClick: () => macotron.settings.open() });
    return rows;
}

function paint() {
    const s = snapshot();
    checkAlerts(s);
    const colorize = opts.colorize !== false;
    macotron.menubar.status("system-metrics", {
        title: "CPU " + s.cpu + "%",
        subtitle: "GPU " + s.gpuN + "%",
        sfSymbol: "cpu",
        color: colorize ? tint(Math.max(s.cpu, s.gpuN)) : undefined,
        menu: menu(s),
    });
    macotron.menubar.add("system-metrics-menu", {
        title: "CPU " + s.cpu + "%  ·  GPU " + s.gpuN + "%",
        icon: "cpu",
        section: "System",
    });
}

paint();
macotron.every(2000, paint);

macotron.command("System Metrics", "Show CPU and GPU usage", () => {
    const s = snapshot();
    macotron.notify.toast("CPU " + s.cpu + "%", "GPU " + s.gpuN + "%");
});
