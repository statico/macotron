const opts = macotron.plugin({
    title: "Fan Control Menu",
    description: "Show fan speed in the menu bar, and keep fans from running slower than a set speed.",
    permissions: ["helper"],
    help: "Click the fan icon in the menu bar to hold the fans at a minimum speed, or return control to macOS.\n\nFan speed always shows. Setting a minimum speed needs the Macotron background helper — use Install on this page.",
    options: {
        clickFloor: {
            type: "dropdown",
            label: "Menu bar click sets",
            default: "100",
            choices: [
                { value: "50", label: "50%" },
                { value: "100", label: "100%" },
            ],
        },
    },
});

const KEY = "fan.floor";

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
        rows.push({ title: "Install background helper…", onClick: () => macotron.settings.open() });
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
        return [{ title: "Speed control", ok: false, message: "Reading speed only. Install the background helper on this page." }];
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

async function setFloor(percent) {
    const s = await macotron.system.setFanFloor(percent);
    if (!s.error) localStorage.setItem(KEY, JSON.stringify(percent));
    render(s);
    if (s.error) {
        if (!s.controllable) {
            macotron.settings.open();
            return;
        }
        macotron.notify.toast("Fan", s.error, { color: "error" });
        return;
    }
    if (percent == null) macotron.notify.toast("Fan", "Set to automatic speed");
    else macotron.notify.toast("Fan", "minimum speed: " + percent + "%", { color: "success" });
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
    setFloor(s.floor ? null : Number(opts.clickFloor) || 100);
}

const initial = snapshot();
render(initial);
// A reload wipes plugin state while the host keeps holding the fans, and an
// app restart drops them entirely, so claim the last chosen floor back —
// unclaimed floors are released once loading finishes.
const saved = initial.floor ?? JSON.parse(localStorage.getItem(KEY) || "null");
if (saved) macotron.system.setFanFloor(saved).then(render);
macotron.every(2000, () => render(snapshot()));

macotron.command("Toggle Fan 100%", "Hold fans at full speed, or restore system default", toggle);
macotron.command("Fan 50%", "Hold fans at half speed, or restore system default", () => {
    const s = snapshot();
    if (!s.controllable) return toggle();
    setFloor(s.floor === 50 ? null : 50);
});
