macotron.plugin({
  title: "Wi-Fi Toggles",
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

async function paint() {
  const wifi = await macotron.network.wifi();
  const bluetooth = await macotron.network.bluetooth();
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
        title: bluetooth.on ? "Turn Bluetooth Off" : "Turn Bluetooth On",
        onClick: () => toast(macotron.network.setBluetooth(!bluetooth.on), "Bluetooth", (r) => r.on ? "On" : "Off"),
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

// `result` may be a promise or a plain object: only the calls that shell out
// hand one back.
async function toast(promise, title, label) {
  const result = await promise;
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
macotron.command("Toggle Wi-Fi", "Turn Wi-Fi on or off", async () => {
  const wifi = await macotron.network.wifi();
  toast(macotron.network.setWifi(!wifi.on), "Wi-Fi", (r) => r.on ? (r.ssid || "On") : "Off");
});
