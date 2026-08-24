// APIs: url.setDefaultHandler, url.on, url.onFallback, url.open, panel, command
const BROWSERS = {
  chrome: { id: "com.google.Chrome", label: "Chrome" },
  safari: { id: "com.apple.Safari", label: "Safari" },
  firefox: { id: "org.mozilla.firefox", label: "Firefox" },
  edge: { id: "com.microsoft.edgemac", label: "Edge" },
  arc: { id: "company.thebrowser.Browser", label: "Arc" },
};

const opts = macotron.plugin({
  title: "Browser Picker",
  description: "Route links by host, then ask or use one browser for everything else.",
  help: "Rules are one per line: host browser. The host can be a JavaScript regex such as /^github\\./i.",
  options: {
    defaultBrowser: {
      type: "dropdown",
      label: "Unmatched links",
      default: "ask",
      choices: [
        { value: "ask", label: "Ask every time" },
        ...Object.entries(BROWSERS).map(([value, browser]) => ({ value, label: browser.label })),
      ],
    },
    rules: {
      type: "text",
      label: "Rules",
      help: "One per line: host browser. The host can be a JavaScript regex such as /^github\\./i.",
      default: "youtube.com safari\nyoutu.be safari",
    },
  },
});

function matcher(value) {
  if (!value.startsWith("/")) return value;
  const end = value.lastIndexOf("/");
  if (end < 1) return value;
  try {
    return new RegExp(value.slice(1, end), value.slice(end + 1));
  } catch {
    return value;
  }
}

const rules = String(opts.rules || "").split("\n").flatMap((line) => {
  const [pattern, browser] = line.trim().split(/\s+/);
  const id = BROWSERS[browser]?.id || browser;
  return pattern && id ? [[matcher(pattern), id]] : [];
});

for (const scheme of ["http", "https"]) {
  macotron.url.setDefaultHandler(scheme);
  for (const [pattern, id] of rules) {
    macotron.url.on(scheme, pattern, (event) => macotron.url.open(event.url, id));
  }
}

function openDefault(event) {
  const browser = BROWSERS[opts.defaultBrowser];
  if (browser) {
    macotron.url.open(event.url, browser.id);
    return;
  }

  const buttons = Object.values(BROWSERS)
    .map(({ id, label }) => `<button onclick='pick(${JSON.stringify(id)})'>${label}</button>`)
    .join(" ");
  const html = `
    ${buttons}
    <script>
      function pick(bundleID) {
        webkit.messageHandlers.macotron.postMessage({ bundleID });
      }
    </script>`;
  const panel = macotron.panel.open({
    title: "Open Link",
    width: 420,
    height: 180,
    html,
    closeOnBlur: true,
  });
  macotron.panel.onMessage(panel, ({ bundleID }) => {
    macotron.url.open(event.url, bundleID);
    macotron.panel.close(panel);
  });
}

macotron.url.onFallback(openDefault);

macotron.command("Open URL", "Open a link, optionally in a specific browser", (args) => {
  const raw = String(args.url || "").trim();
  if (!raw) return macotron.notify.toast("Enter a URL");
  const url = /^[a-z][a-z0-9+.-]*:/i.test(raw) ? raw : "https://" + raw;
  const browser = BROWSERS[args.browser];
  if (browser) {
    macotron.url.open(url, browser.id);
  } else {
    openDefault({ url, host: url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/:?#]+)/i)?.[1] || url });
  }
}, {
  arguments: [
    { name: "url", type: "text", placeholder: "URL", required: true },
    {
      name: "browser",
      type: "dropdown",
      placeholder: "Browser",
      default: "",
      choices: [
        { value: "", label: "Use unmatched-link setting" },
        ...Object.entries(BROWSERS).map(([value, browser]) => ({ value, label: browser.label })),
      ],
    },
  ],
});
