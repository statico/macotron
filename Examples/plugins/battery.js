const opts = macotron.plugin({
    title: "Battery Meter",
    description: "Show charge level and time remaining in the menu bar.",
});

function minutesLabel(n) {
    if (n == null || n < 0) return "";
    const h = Math.floor(n / 60);
    const m = n % 60;
    if (h && m) return h + "h " + m + "m";
    if (h) return h + "h";
    return m + "m";
}

function symbol(level, charging) {
    if (charging) return "battery.100percent.bolt";
    if (level >= 90) return "battery.100percent";
    if (level >= 65) return "battery.75percent";
    if (level >= 40) return "battery.50percent";
    if (level >= 15) return "battery.25percent";
    return "battery.0percent";
}

function snapshot() {
    const bat = macotron.system.battery();
    const level = bat && bat.level != null ? Math.round(bat.level) : -1;
    return {
        level,
        charging: !!(bat && bat.charging),
        charged: !!(bat && bat.charged),
        remaining: bat && bat.timeRemaining,
        toFull: bat && bat.timeToFull,
        source: bat && bat.source,
        health: bat && bat.health,
        cycles: bat && bat.cycles,
        watts: bat && bat.watts,
        lowPowerMode: !!(bat && bat.lowPowerMode),
    };
}

function subtitle(s) {
    if (s.level < 0) return "Power adapter";
    if (s.charged) return "Full";
    if (s.charging) {
        const t = minutesLabel(s.toFull);
        return t ? t + " to full" : "Charging";
    }
    return minutesLabel(s.remaining) || "On battery";
}

function sourceLabel(s) {
    if (s.source === "ac" || s.charging) {
        if (s.charged) return "Power adapter · Charged";
        return "Power adapter · Charging";
    }
    return "On battery";
}

function menu(s) {
    if (s.level < 0) {
        return [
            { title: "Power adapter", icon: "powerplug.fill" },
            { title: "No battery" },
            "-",
            { title: "Battery Settings", icon: "gearshape", onClick: openSettings },
        ];
    }
    const rows = [
        { title: s.level + "%", icon: symbol(s.level, s.charging) },
        { title: sourceLabel(s), icon: s.charging ? "powerplug.fill" : "minus.plus.batteryblock" },
    ];
    if (s.charging && !s.charged) {
        const t = minutesLabel(s.toFull);
        if (t) rows.push({ title: t + " until full", icon: "clock" });
    } else if (!s.charging) {
        const t = minutesLabel(s.remaining);
        if (t) rows.push({ title: t + " remaining", icon: "clock" });
    }
    if (s.health > 0 || s.cycles > 0 || (s.charging && s.watts > 0)) {
        rows.push("-");
        if (s.health > 0) {
            rows.push({ title: "Maximum capacity " + s.health + "%", icon: "heart.fill" });
        }
        if (s.cycles > 0) {
            rows.push({ title: s.cycles + " cycles", icon: "arrow.triangle.2.circlepath" });
        }
        if (s.charging && s.watts > 0) {
            rows.push({ title: s.watts + "W adapter", icon: "bolt.fill" });
        }
    }
    rows.push(
        "-",
        { title: "Low Power Mode: " + (s.lowPowerMode ? "On" : "Off"), icon: "leaf", onClick: enableLowPowerMode },
        "-",
        { title: "Battery Settings", icon: "gearshape", onClick: openSettings }
    );
    return rows;
}

function enableLowPowerMode() {
    const r = macotron.system.setLowPowerMode(true);
    if (r && r.error) {
        macotron.notify.toast("Low Power Mode", r.error, { color: "error" });
        return;
    }
    macotron.notify.toast("Low Power Mode", "On", { color: "success" });
    paint();
}

function openSettings() {
    macotron.url.open("x-apple.systempreferences:com.apple.settings.BATTERY");
}

function paint() {
    const s = snapshot();
    const low = s.level >= 0 && s.level < 20 && !s.charging;
    macotron.menubar.status("battery", {
        title: s.level < 0 ? "AC" : s.level + "%",
        subtitle: subtitle(s),
        sfSymbol: s.level < 0 ? "powerplug.fill" : symbol(s.level, s.charging),
        color: low ? "red" : undefined,
        secondary: true,
        minWidth: 56,
        menu: menu(s),
    });
}

paint();
macotron.every(30000, paint);

macotron.command("Battery", "Show battery level and time remaining", () => {
    const s = snapshot();
    macotron.notify.toast(
        s.level < 0 ? "AC power" : s.level + "%",
        subtitle(s)
    );
});
