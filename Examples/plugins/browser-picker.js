// APIs: url.setDefaultHandler, url.on, url.onFallback, url.open, panel
macotron.plugin({
  title: "Browser Picker",
  description: "Open YouTube in Safari, GitHub in Chrome, and ask which browser to use for other links.",
});

macotron.url.setDefaultHandler("https");
macotron.url.setDefaultHandler("mailto");

macotron.url.on("https", "youtube.com", (ev) => {
  macotron.url.open(ev.url, "com.apple.Safari");
});

macotron.url.on("https", "github.com", (ev) => {
  macotron.url.open(ev.url, "com.google.Chrome");
});

macotron.url.onFallback((ev) => {
  const html = `
    <p>${ev.host}</p>
    <button onclick='pick("com.apple.Safari")'>Safari</button>
    <button onclick='pick("com.google.Chrome")'>Chrome</button>
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
