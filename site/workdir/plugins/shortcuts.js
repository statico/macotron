macotron.plugin({
  title: "Shortcuts",
  description: "Run shortcuts from the launcher.",
});

function refresh() {
  const items = macotron.shortcuts.list().map((name) => ({
    id: name,
    title: name,
    sfSymbol: "square.stack.3d.up",
    onClick: () => macotron.shortcuts.run(name),
  }));
  macotron.launcher.set("shortcuts", items);
}

refresh();
macotron.command("Refresh Shortcuts", "Reload Shortcuts.app names into the launcher", refresh);
