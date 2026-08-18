// demo-power.js
// APIs: macotron.power.preventSleep, macotron.power.allowSleep, macotron.power.isPreventing, macotron.menubar, macotron.command

function refresh() {
    const on = macotron.power.isPreventing();
    macotron.menubar.update("power", {
        title: on ? "Awake ON" : "Awake OFF",
        icon: on ? "cup.and.saucer.fill" : "cup.and.saucer",
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

macotron.menubar.add("power", {
    title: "Awake OFF",
    icon: "cup.and.saucer",
    section: "System",
    onClick: () => {
        toggle();
    },
});

macotron.command("Toggle Keep Awake", "Prevent or allow system sleep", () => {
    toggle();
});
