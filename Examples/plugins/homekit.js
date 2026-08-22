macotron.plugin({
    title: "HomeKit Example",
    description: "Control Home accessories from the menu bar.",
});

function paint() {
    const homes = macotron.homekit.homes();
    const accessories = macotron.homekit.accessories();
    const sensor = accessories.find((a) => a.value != null);
    const menu = homes.length
        ? accessories.map((a) => {
            const row = { title: a.name + (a.on != null ? (a.on ? " · On" : " · Off") : "") };
            if (a.on != null) {
                row.onClick = () => { macotron.homekit.set(a.id, { on: !a.on }); paint(); };
            }
            return row;
        })
        : [{ title: "No HomeKit homes" }];
    macotron.menubar.status("homekit", {
        title: sensor ? String(sensor.value) : "Home",
        sfSymbol: "homekit",
        menu,
    });
}

paint();
macotron.every(60_000, paint);
