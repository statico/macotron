macotron.plugin({
    title: "Night Vision",
    description: "Crush green and blue with the display gamma table.",
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

macotron.command("Toggle Night Vision", "Red-only display gamma", toggle);
