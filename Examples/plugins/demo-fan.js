macotron.plugin({
  title: "Fan",
  description: "Hold a fan-speed floor from the menu bar.",
  permissions: ["fanControl"],
  help: "Click the fan icon in the menu bar to hold a 50% or 100% floor, or restore the system default.\n\nReading fan speed always works. Holding a floor needs the Macotron fan helper — use Install on this page.",
});

function snapshot() {
    return macotron.system.fans();
}

function rpmLine(s) {
    if (!s.available || !s.fans || !s.fans.length) return "No fans on this Mac";
    return s.fans.map((f) => Math.round(f.rpm) + " RPM").join("  ·  ");
}

function floorItem(s, title, percent) {
    const floor = s.floor == null ? null : s.floor;
    const row = { title: (floor === percent ? "✓ " : "") + title };
    if (s.controllable) row.onClick = () => setFloor(percent);
    return row;
}

function menu(s) {
    const rows = [{ title: rpmLine(s) }];
    if (s.error) rows.push({ title: s.error });
    if (!s.available) return rows;
    rows.push("-");
    if (!s.controllable) {
        rows.push({ title: "Install fan helper…", onClick: () => macotron.settings.open() });
        rows.push("-");
    }
    rows.push(floorItem(s, "50%", 50));
    rows.push(floorItem(s, "100%", 100));
    rows.push("-");
    rows.push(floorItem(s, "System default", null));
    return rows;
}

function checkRows(s) {
    if (!s.available) {
        return [{ title: "Speed control", ok: !s.error, message: s.error || "No fans on this Mac" }];
    }
    if (!s.controllable) {
        return [{ title: "Speed control", ok: false, message: "Reading speed only. Install the fan helper on this page." }];
    }
    return [{
        title: "Speed control",
        ok: !s.error,
        message: s.error || (s.floor ? s.floor + "% floor held" : "Ready"),
    }];
}

function render(s) {
    macotron.menubar.status("fan", {
        title: "",
        sfSymbol: s.floor ? "fan.fill" : "fan",
        onClick: toggle,
        menu: menu(s),
    });
    macotron.checks(checkRows(s));
}

function setFloor(percent) {
    const s = macotron.system.setFanFloor(percent);
    render(s);
    if (s.error) {
        if (!s.controllable) {
            macotron.settings.open();
            return;
        }
        macotron.notify.toast("Fan", s.error, { color: "error" });
        return;
    }
    if (percent == null) macotron.notify.toast("Fan", "System default");
    else macotron.notify.toast("Fan", percent + "% floor", { color: "success" });
}

function toggle() {
    const s = snapshot();
    render(s);
    if (!s.available) {
        macotron.notify.toast("Fan", s.error || "No fans on this Mac", { color: s.error ? "error" : "info" });
        return;
    }
    if (!s.controllable) {
        macotron.settings.open();
        return;
    }
    setFloor(s.floor ? null : 100);
}

render(snapshot());
macotron.every(2000, () => render(snapshot()));

macotron.command("Toggle Fan 100%", "Hold fans at full speed, or restore system default", toggle);
