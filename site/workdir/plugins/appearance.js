macotron.plugin({
    title: "Appearance Toggle",
    description: "Switch this Mac between light and dark appearance.",
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
