macotron.plugin({
  title: "USB",
  description: "Announce when a USB device is plugged in, and list attached devices.",
});

macotron.on("usb:changed", (info) => {
  const name = info.name || "Device";
  const verb = info.action === "remove" ? "Removed" : "Attached";
  macotron.notify.toast("USB " + verb, name);
  if (info.action !== "remove") {
    macotron.shell.run("/usr/bin/say", ["Device", name, "connected"]);
  }
});

macotron.command("USB Devices", "List attached USB devices", () => {
  const rows = macotron.usb.list();
  const names = rows.map((d) => d.name).join(", ") || "None";
  macotron.notify.toast("USB", names);
});
