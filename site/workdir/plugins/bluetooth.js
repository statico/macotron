macotron.plugin({
  title: "Bluetooth Device Levels",
  description: "Show battery levels for paired Bluetooth devices in the menu bar.",
});

function clip(name) {
  name = name || "BT";
  return name.length > 12 ? name.slice(0, 11) + "…" : name;
}

async function paint() {
  const bt = await macotron.network.bluetooth();
  const devices = (bt.devices || []).slice().sort((a, b) => {
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
