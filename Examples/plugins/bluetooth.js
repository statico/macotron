macotron.plugin({
  title: "Bluetooth Device Levels",
  description: "Show battery levels for paired Bluetooth and USB input devices in the menu bar.",
});

function clip(name) {
  name = name || "BT";
  return name.length > 12 ? name.slice(0, 11) + "…" : name;
}

// A wired or dongle peripheral never shows up in the Bluetooth list, but a
// few publish their own charge on the HID device. The user cares which of
// their input devices is nearly flat, not which radio it speaks, so those
// earn the same row. Most devices publish nothing and simply never appear.
function hidDevices(known) {
  return (macotron.hid.list() || [])
    .filter((d) => d.battery != null && !known.has(d.name))
    .map((d) => ({ name: d.name, address: d.path, connected: true, battery: d.battery }));
}

async function paint() {
  const bt = await macotron.network.bluetooth();
  const paired = bt.devices || [];
  const devices = paired
    .concat(hidDevices(new Set(paired.map((d) => d.name))))
    .sort((a, b) => {
      if (a.connected !== b.connected) return a.connected ? -1 : 1;
      return (a.name || "").localeCompare(b.name || "");
    });
  let worst = null;
  for (const d of devices) {
    if (!d.connected || d.battery == null) continue;
    if (!worst || d.battery < worst.battery) worst = d;
  }
  macotron.menubar.status("bluetooth", {
    title: worst ? clip(worst.name) + " " + worst.battery + "%" : "BT",
    sfSymbol: worst ? "battery.100percent" : "antenna.radiowaves.left.and.right",
    menu: devices.map((d) => ({
      title: d.name + "    " + (d.battery != null ? d.battery + "%" : "—"),
    })),
  });
}

paint();
macotron.every(60_000, paint);
