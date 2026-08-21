macotron.plugin({
  title: "Eject",
  description: "Eject disks from the menu bar, and empty the Trash.",
});

function userVolumes(names) {
  return (names || []).filter((n) => {
    if (!n || n.charAt(0) === ".") return false;
    return n !== "Macintosh HD" && n !== "Macintosh HD - Data" && n !== "Data";
  });
}

function emptyTrash() {
  if (!confirm("Empty the Trash?")) return;
  macotron.shell.run("/usr/bin/osascript", ["-e", 'tell application "Finder" to empty the trash']);
}

function paint() {
  const names = userVolumes(macotron.fs.list("/Volumes"));
  const menu = names.length
    ? names.map((name) => ({
        title: "Eject " + name,
        onClick: () => macotron.shell.run("/usr/sbin/diskutil", ["eject", "/Volumes/" + name]),
      }))
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
