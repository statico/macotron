macotron.plugin({
  title: "HID",
  description: "List keyboards, mice, and other input devices on this Mac.",
});

macotron.command("HID Devices", "List attached HID devices", () => {
  const rows = macotron.hid.list();
  const names = rows
    .map((d) => d.name + " (" + hex(d.vendorID) + "/" + hex(d.productID) + ")")
    .join(", ") || "None";
  macotron.notify.toast("HID", names);
});

function hex(n) {
  return n.toString(16).padStart(4, "0");
}
