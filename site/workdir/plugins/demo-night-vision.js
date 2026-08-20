macotron.plugin({
    title: "Night Vision",
    description: "Tint the display red for dark rooms.",
});

let on = false;

function toggle() {
    on = !on;
    if (on) {
        macotron.display.setGamma({ red: 1, green: 0, blue: 0 });
        macotron.notify.toast("Night vision", "On", { color: "success" });
    } else {
        macotron.display.restoreGamma();
        macotron.notify.toast("Night vision", "Off");
    }
}

macotron.command("Toggle Night Vision", "Tint the display red", toggle);
