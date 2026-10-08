macotron.plugin({
    title: "Home Scenes",
    description: "Run Home scenes from the menu bar. Each scene is a shortcut in the Shortcuts folder named Home.",
});

async function paint() {
    const scenes = await macotron.homekit.scenes();
    const menu = scenes.length
        ? scenes.map((name) => ({
            title: name,
            onClick: async () => {
                const ok = await macotron.homekit.run(name);
                macotron.notify.toast(name, ok ? "Done" : "Failed", { color: ok ? "success" : "error" });
            },
        }))
        : [{ title: "Add shortcuts to a Shortcuts folder named Home" }];
    macotron.menubar.status("homekit", { title: "", sfSymbol: "homekit", menu });
}

paint();
macotron.every(5 * 60_000, paint);
