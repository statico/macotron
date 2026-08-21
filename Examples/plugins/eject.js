macotron.plugin({
  title: "Eject",
  description: "Eject volumes from the menu bar.",
});

function userVolumes(names) {
  return (names || []).filter((n) => {
    if (!n || n.charAt(0) === ".") return false;
    return n !== "Macintosh HD" && n !== "Macintosh HD - Data" && n !== "Data";
  });
}

function paint() {
  const names = userVolumes(macotron.fs.list("/Volumes"));
  macotron.menubar.status("eject", {
    title: "",
    sfSymbol: "eject.fill",
    menu: names.length
      ? names.map((name) => ({
          title: "Eject " + name,
          onClick: () => macotron.shell.run("/usr/sbin/diskutil", ["eject", "/Volumes/" + name]),
        }))
      : [{ title: "No volumes" }],
  });
}

paint();
