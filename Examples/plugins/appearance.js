macotron.plugin({
    title: "Appearance Toggle",
    description: "Switch this Mac between light and dark appearance.",
});

macotron.command("Cycle Appearance", "Switch system appearance between light, dark, and auto", () => {
    const next = { light: "dark", dark: "auto", auto: "light" }[macotron.system.appearance()];
    macotron.system.setAppearance(next).then((result) => {
        if (!result.ok) {
            macotron.notify.toast("Appearance", result.error || "Failed", { color: "failure" });
            return;
        }
        const label = result.appearance[0].toUpperCase() + result.appearance.slice(1);
        macotron.notify.toast("Appearance", label, { color: "success" });
    });
});

macotron.command("Toggle Dark Mode", "Switch system appearance between light and dark", () => {
    macotron.system.setDarkMode(!macotron.system.darkMode()).then((result) => {
        if (!result.ok) {
            macotron.notify.toast("Appearance", result.error || "Failed", { color: "failure" });
            return;
        }
        macotron.notify.toast("Appearance", result.darkMode ? "Dark" : "Light", { color: "success" });
    });
});
