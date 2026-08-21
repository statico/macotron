macotron.plugin({
  title: "Wi-Fi",
  description: "Turn Wi-Fi, Bluetooth, and AirDrop on or off from the menu bar.",
});

function clip(name) {
  name = name || "Off";
  return name.length > 15 ? name.slice(0, 14) + "…" : name;
}

function airDropLabel(mode) {
  if (mode === "everyone") return "Everyone";
  if (mode === "contacts") return "Contacts Only";
  return "Off";
}

function paint() {
  const wifi = macotron.network.wifi();
  const title = !wifi.available ? "No Wi-Fi" : wifi.on ? clip(wifi.ssid || "On") : "Wi-Fi Off";
  macotron.menubar.status("wifi", {
    title: title,
    sfSymbol: wifi.on ? "wifi" : "wifi.slash",
    menu: [
      {
        title: wifi.on ? "Turn Wi-Fi Off" : "Turn Wi-Fi On",
        onClick: () => toast(macotron.network.setWifi(!wifi.on), "Wi-Fi", (r) => r.on ? (r.ssid || "On") : "Off"),
      },
      {
        title: macotron.network.bluetooth().on ? "Turn Bluetooth Off" : "Turn Bluetooth On",
        onClick: () => {
          const on = !macotron.network.bluetooth().on;
          toast(macotron.network.setBluetooth(on), "Bluetooth", (r) => r.on ? "On" : "Off");
        },
      },
      {
        title: "AirDrop: " + airDropLabel(macotron.network.airDrop().mode),
        menu: [
          { title: "Off", onClick: () => setAirDrop("off") },
          { title: "Contacts Only", onClick: () => setAirDrop("contacts") },
          { title: "Everyone", onClick: () => setAirDrop("everyone") },
        ],
      },
    ],
  });
}

function toast(result, title, label) {
  if (!result.ok) {
    macotron.notify.toast(title, result.error || "Failed", { color: "failure" });
    return;
  }
  macotron.notify.toast(title, label(result), { color: "success" });
  paint();
}

function setAirDrop(mode) {
  toast(macotron.network.setAirDrop(mode), "AirDrop", () => airDropLabel(mode));
}

macotron.on("wifi:changed", paint);
paint();
macotron.command("Toggle Wi-Fi", "Turn Wi-Fi on or off", () => {
  const on = !macotron.network.wifi().on;
  toast(macotron.network.setWifi(on), "Wi-Fi", (r) => r.on ? (r.ssid || "On") : "Off");
});
