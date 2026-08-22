const opts = macotron.plugin({
  title: "Profiles Example",
  description: "Use light appearance on your home Wi-Fi and dark appearance at work.",
  options: {
    homeSSID: { type: "string", label: "Home Wi-Fi name", default: "" },
    workSSID: { type: "string", label: "Work Wi-Fi name", default: "" },
  },
});

function apply(ssid) {
  if (!ssid) return;
  if (opts.homeSSID && ssid === opts.homeSSID) {
    macotron.system.setDarkMode(false);
    macotron.notify.toast("Profile", "Home");
    return;
  }
  if (opts.workSSID && ssid === opts.workSSID) {
    macotron.system.setDarkMode(true);
    macotron.notify.toast("Profile", "Work");
  }
}

function check(info) {
  apply((info && info.ssid) || (macotron.network.wifi() || {}).ssid);
}

macotron.on("wifi:changed", check);
check(macotron.network.wifi());
