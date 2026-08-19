// demo-power.js
// APIs: macotron.power.preventSleep, macotron.power.allowSleep, macotron.power.isPreventing, macotron.menubar, macotron.command

function refresh() {
    const on = macotron.power.isPreventing();
    macotron.menubar.status("power", {
        title: on ? "Awake" : "Sleep",
        sfSymbol: on ? "cup.and.saucer.fill" : "cup.and.saucer",
        color: on ? "orange" : null,
        bold: on,
        menu: [
            { title: on ? "Allow Sleep" : "Keep Awake", onClick: toggle },
        ],
    });
}

function toggle() {
    if (macotron.power.isPreventing()) {
        macotron.power.allowSleep();
    } else {
        macotron.power.preventSleep({ reason: "Macotron keep awake" });
    }
    refresh();
}

refresh();

macotron.command("Toggle Keep Awake", "Prevent or allow system sleep", () => {
    toggle();
});
