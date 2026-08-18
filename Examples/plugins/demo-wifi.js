// demo-wifi.js
// APIs: macotron.network.wifiSSID, macotron.network.interfaces, macotron.on("wifi:changed"), macotron.notify, macotron.command

macotron.on("wifi:changed", (info) => {
    macotron.notify.show("Wi-Fi", info.ssid || "Disconnected");
});

macotron.command("Wi-Fi SSID", "Show the current Wi-Fi network name", () => {
    const ssid = macotron.network.wifiSSID();
    macotron.notify.show("Wi-Fi", ssid || "Not connected");
});
