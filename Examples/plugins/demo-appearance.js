macotron.plugin({
    title: "Appearance",
    description: "Toggle system light and dark mode.",
});

macotron.command("Toggle Dark Mode", "Switch system appearance between light and dark", () => {
    const result = macotron.system.setDarkMode(!macotron.system.darkMode());
    if (!result.ok) {
        macotron.notify.toast("Appearance", result.error || "Failed", { color: "failure" });
        return;
    }
    macotron.notify.toast("Appearance", result.darkMode ? "Dark" : "Light", { color: "success" });
});
