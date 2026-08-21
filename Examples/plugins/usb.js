macotron.plugin({
  title: "USB",
  description: "Toast when a USB device is plugged in.",
});

macotron.on("usb:changed", (info) => {
  const verb = info.action === "remove" ? "Removed" : "Attached";
  macotron.notify.toast("USB " + verb, info.name || "Device");
});

macotron.command("USB Devices", "List attached USB devices", () => {
  const rows = macotron.usb.list();
  const names = rows.map((d) => d.name).join(", ") || "None";
  macotron.notify.toast("USB", names);
});
