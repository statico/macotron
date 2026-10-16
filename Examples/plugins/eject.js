macotron.plugin({
  title: "Eject Disks from Menu Bar",
  description: "Eject disks from the menu bar, and empty the Trash.",
});

// The disks Finder puts an eject button next to: removable media, disk
// images and server volumes. The startup disk and its siblings never qualify.
function ejectable(volumes) {
  return (volumes || []).filter((v) => !v.root && (v.ejectable || v.network));
}

function emptyTrash() {
  if (!confirm("Empty the Trash?")) return;
  macotron.shell.run("/usr/bin/osascript", ["-e", 'tell application "Finder" to empty the trash']);
}

async function eject(volume) {
  const r = await macotron.disks.eject(volume.path);
  if (!r.ok) {
    macotron.notify.toast("Could not eject " + volume.name, r.error, { color: "error" });
    return;
  }
  paint();
}

function paint() {
  const volumes = ejectable(macotron.disks.list());
  const menu = volumes.length
    ? volumes.map((v) => ({ title: "Eject " + v.name, onClick: () => eject(v) }))
    : [{ title: "No volumes" }];
  menu.push({ title: "Empty Trash", onClick: emptyTrash });
  macotron.menubar.status("eject", {
    title: "",
    sfSymbol: "eject.fill",
    menu,
  });
}

paint();
macotron.command("Empty Trash", "Empty the Trash", emptyTrash);
