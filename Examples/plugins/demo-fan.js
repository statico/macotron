macotron.plugin({
  title: "Fan",
  description: "Hold a fan-speed floor from the menu bar.",
  help: "Click the fan icon in the menu bar to hold a 50% or 100% floor, or restore the system default. There is nothing to configure here — a keyboard shortcut is optional.\n\nIf a toast says administrator access or SMC error, this Mac is blocking fan-speed writes. That is a system limit, not a missing setting.",
});

function snapshot() {
    return macotron.system.fans();
}

function rpmLine(s) {
    if (!s.available || !s.fans || !s.fans.length) return "No fans on this Mac";
    return s.fans.map((f) => Math.round(f.rpm) + " RPM").join("  ·  ");
}

function menu(s) {
    const floor = s.floor == null ? null : s.floor;
    const rows = [{ title: rpmLine(s) }, "-"];
    rows.push({
        title: (floor === 50 ? "✓ " : "") + "50%",
        onClick: () => setFloor(50),
    });
    rows.push({
        title: (floor === 100 ? "✓ " : "") + "100%",
        onClick: () => setFloor(100),
    });
    rows.push("-");
    rows.push({
        title: (floor == null ? "✓ " : "") + "System default",
        onClick: () => setFloor(null),
    });
    return rows;
}

let lastError = "";

function paint() {
    const s = snapshot();
    macotron.menubar.status("fan", {
        title: "",
        sfSymbol: s.floor ? "fan.fill" : "fan",
        onClick: toggle,
        menu: menu(s),
    });
    if (s.error && s.error !== lastError) {
        lastError = s.error;
        macotron.notify.toast("Fan", s.error, { color: "error" });
    }
    if (!s.error) lastError = "";
    macotron.checks([{
        title: "Speed control",
        ok: !s.error,
        message: s.error || (s.available ? "Ready" : "No fans on this Mac"),
    }]);
}

function setFloor(percent) {
    const s = macotron.system.setFanFloor(percent);
    paint();
    if (s.error) return;
    if (percent == null) macotron.notify.toast("Fan", "System default");
    else macotron.notify.toast("Fan", percent + "% floor", { color: "success" });
}

function toggle() {
    const s = snapshot();
    if (!s.available) {
        macotron.notify.toast("Fan", s.error || "No fans on this Mac", { color: s.error ? "error" : "info" });
        return;
    }
    setFloor(s.floor ? null : 100);
}

paint();
macotron.every(2000, paint);

macotron.command("Toggle Fan 100%", "Hold fans at full speed, or restore system default", toggle);
