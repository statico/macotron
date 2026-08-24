// APIs: url.setDefaultHandler, url.on, url.onFallback, url.open, panel
const opts = macotron.plugin({
  title: "Browser Picker",
  description: "Send links to the right browser by host, and ask which to use for the rest.",
  options: {
    rules: {
      type: "text",
      label: "Rules (host, then bundle ID)",
      default: "youtube.com com.apple.Safari\ngithub.com com.google.Chrome",
    },
    browsers: {
      type: "text",
      label: "Ask me between (bundle ID, then name)",
      default: "com.apple.Safari Safari\ncom.google.Chrome Chrome",
    },
  },
});

// Both options are "one entry per line, first word is the key".
function pairs(text) {
  return String(text || "")
    .split("\n")
    .map((line) => line.trim().split(/\s+/))
    .filter(([key, value]) => key && value)
    .map(([key, ...rest]) => [key, rest.join(" ")]);
}

macotron.url.setDefaultHandler("https");
macotron.url.setDefaultHandler("mailto");

for (const [host, bundleID] of pairs(opts.rules)) {
  // Registering the bare host misses www., which is how half the web links.
  for (const name of [host, "www." + host]) {
    macotron.url.on("https", name, (ev) => macotron.url.open(ev.url, bundleID));
  }
}

macotron.url.onFallback((ev) => {
  const buttons = pairs(opts.browsers)
    .map(([bundleID, name]) => `<button onclick='pick(${JSON.stringify(bundleID)})'>${name}</button>`)
    .join(" ");
  const html = `
    <p>${ev.host}</p>
    ${buttons}
    <script>
      function pick(id) {
        window.webkit.messageHandlers.macotron.postMessage({ url: ${JSON.stringify(ev.url)}, bundleID: id });
      }
    </script>`;
  const id = macotron.panel.open({ title: "Open link", width: 360, height: 180, html, closeOnBlur: true });
  macotron.panel.onMessage(id, (msg) => {
    macotron.url.open(msg.url, msg.bundleID);
    macotron.panel.close(id);
  });
});
