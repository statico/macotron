// APIs: url.setDefaultHandler, url.on, url.open, fs.read, checks, panel, command
// `dataDir` marks a Chromium browser: only those take a profile, read from
// `<dataDir>/Local State`.
const BROWSERS = {
  chrome: { id: "com.google.Chrome", label: "Chrome", dataDir: "~/Library/Application Support/Google/Chrome" },
  safari: { id: "com.apple.Safari", label: "Safari" },
  firefox: { id: "org.mozilla.firefox", label: "Firefox" },
  edge: { id: "com.microsoft.edgemac", label: "Edge", dataDir: "~/Library/Application Support/Microsoft Edge" },
  arc: { id: "company.thebrowser.Browser", label: "Arc" },
};

const RULES_HELP = "One rule per line: pattern browser[:profile]. The first matching line wins. The pattern is a host (matches subdomains), host/path (path prefix), * (any link), or a regex on the host such as /^github\\./i. A Chrome or Edge profile is its folder (find it in chrome://version under Profile Path) or its name.";

const opts = macotron.plugin({
  title: "Browser Picker",
  description: "Route links by host or path to a browser or a Chrome profile; ask or use one browser for everything else.",
  help: RULES_HELP,
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
      help: RULES_HELP,
      default: "youtube.com safari\nyoutu.be safari",
    },
  },
});

const problems = [];

// Folder for a profile given as its folder or as a display name used by
// exactly one profile. Guessing between two "Work" profiles would send links
// to the wrong account, so anything ambiguous comes back null.
function profileFolder(browser, profile) {
  let cache;
  try {
    cache = JSON.parse(macotron.fs.read(browser.dataDir + "/Local State")).profile.info_cache;
  } catch {
    return { error: `can't read ${browser.label} profiles` };
  }
  if (cache[profile]) return { folder: profile };
  const named = Object.keys(cache).filter((folder) => cache[folder].name?.toLowerCase() === profile.toLowerCase());
  if (named.length === 1) return { folder: named[0] };
  return { error: named.length ? `${named.length} ${browser.label} profiles are named "${profile}"` : `no ${browser.label} profile "${profile}"` };
}

function hostMatcher(pattern) {
  if (pattern === "*") return () => true;
  if (pattern.startsWith("/")) {
    const end = pattern.lastIndexOf("/");
    const re = new RegExp(pattern.slice(1, end), pattern.slice(end + 1)); // throws on a bad regex
    return (event) => re.test(event.host);
  }
  const slash = pattern.indexOf("/");
  const host = (slash < 0 ? pattern : pattern.slice(0, slash)).toLowerCase();
  const path = slash < 0 ? "" : pattern.slice(slash).replace(/\/+$/, "").toLowerCase();
  return (event) => {
    const h = String(event.host || "").toLowerCase();
    const p = String(event.path || "").toLowerCase();
    // Whole labels and whole segments: example.com is not badexample.com,
    // /acme is not /acme-evil.
    return (h === host || h.endsWith("." + host)) && (!path || p === path || p.startsWith(path + "/"));
  };
}

function parseRule(line) {
  let rest = line.trim();
  let pattern = null;
  let from = null;
  // `from:` may sit before or after the pattern; the browser is whatever is
  // left, so a profile can contain spaces ("Profile 1").
  while (rest && (pattern === null || rest.startsWith("from:"))) {
    const [token] = rest.split(/\s/, 1);
    rest = rest.slice(token.length).trim();
    if (token.startsWith("from:")) from = token.slice(5);
    else pattern = token;
  }
  if (!pattern || !rest) throw new Error("needs a pattern and a browser");
  const colon = rest.indexOf(":");
  const name = colon < 0 ? rest : rest.slice(0, colon).trim();
  let profile = colon < 0 ? undefined : rest.slice(colon + 1).trim() || undefined;
  const browser = BROWSERS[name];
  if (!browser && (!name.includes(".") || /\s/.test(name))) throw new Error(`unknown browser "${name}"`);
  const matchesHost = hostMatcher(pattern);
  if (profile && !browser?.dataDir) {
    problems.push(`${line}: ${browser?.label || name} has no profiles`);
    profile = undefined;
  } else if (profile) {
    const resolved = profileFolder(browser, profile);
    if (resolved.error) problems.push(`${line}: ${resolved.error}`);
    profile = resolved.folder;
  }
  return {
    line,
    id: browser?.id || name,
    profile,
    matches: (event) => (!from || event.sourceBundle === from) && matchesHost(event),
  };
}

const rules = String(opts.rules || "").split("\n").filter((line) => line.trim()).flatMap((line) => {
  try {
    return [parseRule(line.trim())];
  } catch (err) {
    problems.push(`${line.trim()}: ${err.message}`);
    return [];
  }
});

macotron.checks(problems.length
  ? problems.map((message) => ({ title: "Rule skipped or changed", ok: false, message }))
  : [{ title: "Rules", ok: true, message: `${rules.length} rule${rules.length === 1 ? "" : "s"}` }]);

function route(event) {
  const rule = rules.find((r) => r.matches(event));
  // A rule whose browser isn't installed still falls through, so no link
  // vanishes. Host only in the log: full URLs can carry tokens.
  if (rule && macotron.url.open(event.url, rule.id, rule.profile)) {
    macotron.log("browser-picker:", event.host, "->", rule.line, "->", rule.id, rule.profile || "");
    return;
  }
  openDefault(event);
}

for (const scheme of ["http", "https"]) {
  macotron.url.setDefaultHandler(scheme);
  // Scoped to the schemes a browser can actually open. A global onFallback
  // would also swallow mailto: and every other scheme Macotron registers,
  // hand them to a browser, and strand them there.
  macotron.url.on(scheme, "*", route);
}

const ROW = 36;
const GAP = 12;

function openDefault(event) {
  const browser = BROWSERS[opts.defaultBrowser];
  if (browser) {
    macotron.url.open(event.url, browser.id);
    return;
  }

  const list = Object.values(BROWSERS);
  const buttons = list
    .map(({ id, label }) => `<button onclick='pick(${JSON.stringify(id)})'>${label}</button>`)
    .join(" ");
  const html = `
    <style>button { height: ${ROW}px; }</style>
    ${buttons}
    <script>
      function pick(bundleID) {
        webkit.messageHandlers.macotron.postMessage({ bundleID });
      }
    </script>`;
  const panel = macotron.panel.open({
    title: "Open Link",
    width: 420,
    // Panel body is 16px padding with a 12px flex gap, so the buttons decide
    // the height — a fixed one would scroll once a browser is added.
    height: 32 + list.length * ROW + (list.length - 1) * GAP,
    html,
    closeOnBlur: true,
  });
  macotron.panel.onMessage(panel, ({ bundleID }) => {
    macotron.url.open(event.url, bundleID);
    macotron.panel.close(panel);
  });
}

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
