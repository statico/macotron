// demo-wifi.js
// APIs: macotron.network.wifiSSID, macotron.network.interfaces, macotron.on("wifi:changed"), macotron.notify, macotron.command

macotron.plugin({
  title: "Wi-Fi",
  description: "Show the current network name.",
});

let lastChange = null;

macotron.on("wifi:changed", (info) => {
    lastChange = info.ssid || "Disconnected";
});

macotron.command("Wi-Fi SSID", "Show the current Wi-Fi network name", () => {
    const ssid = macotron.network.wifiSSID() || "Not connected";
    macotron.notify.toast("Wi-Fi", lastChange ? `${ssid} — last change: ${lastChange}` : ssid);
});
