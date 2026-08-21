macotron.plugin({
  title: "Spaces",
  description: "Switch to the next Mission Control desktop.",
  permissions: ["accessibility"],
});

function nextSpace() {
  const spaces = macotron.spaces.list().filter((s) => s.type === "user");
  if (!spaces.length) {
    macotron.notify.toast("Spaces", "None found");
    return;
  }
  const current = macotron.spaces.current();
  const i = Math.max(0, spaces.findIndex((s) => s.id === current?.id));
  const next = spaces[(i + 1) % spaces.length];
  macotron.spaces.go(next.desktop);
}

macotron.on("space:changed", (space) => {
  if (space && space.desktop) {
    macotron.notify.toast("Space", "Desktop " + space.desktop);
  }
});

macotron.command("Next Space", "Switch to the next desktop", nextSpace);
