// demo-wifi.js
// APIs: macotron.network.wifiSSID, macotron.network.interfaces, macotron.on("wifi:changed"), macotron.notify, macotron.command

let lastChange = null;

macotron.on("wifi:changed", (info) => {
    lastChange = info.ssid || "Disconnected";
});

macotron.command("Wi-Fi SSID", "Show the current Wi-Fi network name", () => {
    const ssid = macotron.network.wifiSSID() || "Not connected";
    macotron.notify.show("Wi-Fi", lastChange ? `${ssid} — last change: ${lastChange}` : ssid);
});
