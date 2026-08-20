const CARDS = [
  ["Quick launcher", "Cmd-Space style launcher for apps and commands."],
  ["Fuzzy search", "Type a few letters. Matches rank as you go."],
  ["Starred rows", "Pin launcher items with ⌘S so they show on open."],
  ["Command shortcuts", "Assign a key to any launcher command."],
  ["Global hotkeys", "Carbon hotkeys, overridable in Settings."],
  ["Tile windows", "Halves, corners, center, or another display."],
  ["Drag-to-snap", "Pull a window to an edge or corner to tile."],
  ["Switch windows", "Pick an open window by name and raise it."],
  ["Minimize / close", "Drive window chrome from a script."],
  ["Fullscreen", "Toggle native fullscreen on the focused window."],
  ["Window events", "React when a window is created or focused."],
  ["Move by frame", "Set exact pixels or display fractions."],
  ["Menu bar extras", "Icons, two-line text, click menus beside Macotron."],
  ["Icon tint", "Recolor the Macotron glyph from a plugin."],
  ["System banners", "UserNotifications from a one-liner."],
  ["HUD toasts", "One-line overlay under the cursor."],
  ["HTML panels", "Small WKWebView windows for custom UI."],
  ["Liquid Glass", "Translucent Tahoe panels, regular or clear."],
  ["Frameless panels", "No title bar. Escape closes."],
  ["Screenshot", "Full display PNG, or drag a rectangle."],
  ["Color picker", "System magnifier eyedropper, hex plus RGB."],
  ["OCR", "Read text from a file or a screenshot."],
  ["Spotlight search", "NSMetadataQuery from plugin code."],
  ["Clipboard text", "Get and set the pasteboard."],
  ["Clipboard images", "Push a PNG onto the pasteboard."],
  ["Clipboard history", "Browse, paste, or drop old clips."],
  ["Snippets", "Abbreviation expansion as you type."],
  ["Now Playing", "Title, artist, artwork, play/pause, skip."],
  ["Keep awake", "IOPM assertion so the Mac stays up."],
  ["Lock screen", "Lock now from a hotkey."],
  ["Sleep", "Put the machine to sleep."],
  ["Sleep events", "Hear system:sleep, wake, lock, unlock."],
  ["Wi-Fi", "SSID, on/off, and interface IPs."],
  ["Bluetooth", "Radio toggle plus connected devices."],
  ["AirDrop", "Off, Contacts Only, or Everyone."],
  ["Idle time", "Seconds since the last HID event."],
  ["Idle hooks", "system:idle and system:active callbacks."],
  ["CPU usage", "Percent since the last sample."],
  ["GPU usage", "Name and load when the OS reports it."],
  ["Memory", "Total, used, and free."],
  ["Disk", "Volume capacity from a plugin."],
  ["Processes", "Top CPU hogs by name and pid."],
  ["CPU temperature", "Read the thermal sensor."],
  ["Fan RPM", "Current speed; no privileges to read."],
  ["Fan floor", "Hold 50% or 100% via the helper."],
  ["Battery level", "Percent, charging, time remaining."],
  ["Battery health", "Max capacity, cycles, adapter watts."],
  ["Low Power Mode", "Flip pmset with an admin prompt."],
  ["Dark mode", "Read and set system appearance."],
  ["Focus status", "Whether a Focus mode is on."],
  ["Brightness", "Get and set display brightness."],
  ["XDR", "Toggle the extra-bright range."],
  ["Gamma LUT", "Per-channel white and black points."],
  ["Night vision", "Red-only gamma for dark rooms."],
  ["Extra dark", "Dim below the hardware minimum."],
  ["Invert display", "Swap white and black in the LUT."],
  ["Display list", "Frames, scale, serial, millimeters."],
  ["Display events", "Add, remove, move, mirror, mode."],
  ["Post clicks", "HID click at a Cocoa point."],
  ["Post keys", "Key downs with modifier flags."],
  ["Unicode type", "Paste characters the OS will type."],
  ["Scroll", "Pixel or line scroll events."],
  ["HID tap", "Listen, and swallow events if you want."],
  ["Mouse warp", "Move the cursor. Read buttons."],
  ["Launch apps", "Open by bundle ID via Launch Services."],
  ["Switch apps", "Bring a running app forward."],
  ["Hide / quit", "Hide or terminate by bundle ID."],
  ["App menus", "Choose File → New from a script."],
  ["App events", "activated, launched, terminated."],
  ["Audio devices", "List inputs and outputs."],
  ["Default output", "Cycle speakers or a USB DAC."],
  ["Volume", "0 to 1 on the system or a device."],
  ["Mute", "Toggle mute without touching volume."],
  ["Spaces", "List Mission Control desktops."],
  ["Switch desktop", "Go by number, id, or display."],
  ["Move to space", "SkyLight when SIP allows it."],
  ["USB", "Name, vendor, attach and detach."],
  ["Shortcuts.app", "List and run user shortcuts."],
  ["Calendar", "Upcoming events for the next N hours."],
  ["Meetings", "Next event in the menu bar."],
  ["Notes", "List Apple Notes and open one."],
  ["Contacts", "Search names, emails, phones."],
  ["URL schemes", "Register macotron:// handlers."],
  ["Open in browser", "Pick Safari, a profile, or another app."],
  ["HTTP", "GET/POST/PUT/DELETE from plugins."],
  ["Read files", "Text or base64 bytes. ~ expands."],
  ["Write files", "Overwrite a path from a plugin."],
  ["Rename", "Atomic rename; fails if the dest exists."],
  ["Watch files", "FSEvents callback on change."],
  ["Shell", "Allowlisted Apple tools with a prompt."],
  ["Keychain", "Secrets that never hit settings.json."],
  ["Plugin options", "Text, toggles, dropdowns, files, keys."],
  ["Password options", "Keychain-backed fields in Settings."],
  ["Plugin checks", "Orange warning when something is blocked."],
  ["Apple Intelligence", "On-device Foundation Models."],
  ["Claude", "Anthropic chat and streaming."],
  ["Gemini", "Google models from a plugin."],
  ["OpenAI", "Same chat/stream shape."],
  ["Token stream", "Push chunks into a panel as they arrive."],
  ["Hot reload", "Save a .js file. The host reloads it."],
  ["Git workdir", "Optional git init. Agents commit."],
  ["Stock Mac", "No Homebrew, npm, or extra binaries."],
  ["QuickJS", "Embedded engine, bytecode cache."],
  ["ES modules", "import/export with a custom loader."],
  ["localStorage", "JSON store in the workdir."],
  ["Settings UI", "Per-plugin page, shortcuts, checks."],
  ["First-run wizard", "Pick a folder. Seed README once."],
  ["AGENTS.md", "App-owned instructions for coding agents."],
  ["Launcher rows", "Plugins inject extra results."],
  ["Command args", "Text, number, and dropdown prompts."],
  ["Locale", "Language, region, metric vs US units."],
  ["Network bytes", "Interface counters in and out."],
  ["Weather menu", "wttr.in in the menu bar."],
  ["Pomodoro", "Timer plus a status item."],
  ["Calculator", "A tiny glass panel."],
  ["Regex workbench", "Test a pattern against a haystack."],
  ["File search UI", "Spotlight results in a frameless panel."],
  ["Disk usage", "df/du in a readable panel."],
  ["Dev utils", "UUID, timestamp, Base64, JWT peek."],
  ["Lorem ipsum", "Generate placeholder text to the clipboard."],
  ["ISO date", "Stamp the clipboard with now()."],
  ["Batch rename", "Prefix Downloads with YYYY-MM-DD."],
  ["HEIC to JPEG", "sips conversion on a stock Mac."],
  ["Screenshot rename", "OCR the latest Desktop capture."],
  ["Present mode", "Hide desktop clutter for a talk."],
  ["Security checklist", "FileVault, firewall, SIP probes."],
  ["Frontmost app", "React when the user switches focus."],
  ["Clipboard images UI", "Browse image clips and paste."],
  ["Community plugins", "GitHub topic macotron-plugin."],
  ["Direct download", "No App Store. Optional Homebrew cask."],
];

const APIS = [
  ["macotron.window", [
    "List, focus, minimize, close, fullscreen",
    "move / moveToFraction across displays",
    "Drag-to-edge snap maps",
    "window:created, window:focused",
  ]],
  ["macotron.keyboard", [
    "Global hotkeys with Settings override",
    "Modifier flags (cmd, opt, fn, ...)",
  ]],
  ["macotron.event / mouse", [
    "Post click, key, unicode, scroll",
    "HID tap; return false to swallow",
    "Cursor location, warp, buttons",
  ]],
  ["macotron.display", [
    "List frames, scale, serial, mm",
    "Brightness and XDR",
    "Gamma LUT, restore ColorSync",
    "display:changed flags",
  ]],
  ["macotron.system", [
    "CPU, GPU, memory, disk, processes",
    "Temperature and fan RPM / floor",
    "Battery, health, Low Power Mode",
    "Dark mode, Focus, locale",
  ]],
  ["macotron.power", [
    "Prevent / allow sleep",
    "Lock and sleep now",
    "system:sleep, wake, lock, unlock",
  ]],
  ["macotron.audio", [
    "Devices, default in/out",
    "Volume and mute",
    "audio:changed",
  ]],
  ["macotron.network", [
    "Wi-Fi SSID and radio",
    "Bluetooth devices",
    "AirDrop mode, interface IPs",
  ]],
  ["macotron.app", [
    "List, launch, switch, hide, quit",
    "Choose an AX menu path",
    "app:activated / launched / terminated",
  ]],
  ["macotron.spaces", [
    "Mission Control desktops",
    "go() by index or id",
    "moveWindow when SIP allows",
  ]],
  ["macotron.screen", [
    "Full or selection capture",
    "System color picker",
  ]],
  ["macotron.ocr", ["Recognize text from a path or image"]],
  ["macotron.clipboard", [
    "Text, images, UTIs",
    "History, paste, remove",
  ]],
  ["macotron.snippets", ["List, set, insert, expansion on/off"]],
  ["macotron.fs", ["read, write, list, rename, watch, exists"]],
  ["macotron.shell", ["Allowlisted Apple CLI with a prompt"]],
  ["macotron.http", ["get, post, put, delete"]],
  ["macotron.ai", [
    "local, claude, anthropic, gemini, openai",
    "chat and stream with onChunk",
  ]],
  ["macotron.panel", [
    "html or rawHtml, glass, frameless",
    "postMessage / onMessage",
  ]],
  ["macotron.menubar", [
    "Menu rows and extra status items",
    "SF Symbols, images, two-line text",
    "setIcon / setIconColor / setTitle",
  ]],
  ["macotron.notify", ["System banners and HUD toasts"]],
  ["macotron.media", ["Now Playing snapshot, play/pause, skip"]],
  ["macotron.calendar", ["Upcoming events with times and location"]],
  ["macotron.notes", ["List and open Apple Notes"]],
  ["macotron.contacts", ["List and search"]],
  ["macotron.spotlight", ["Metadata search: path, name, kind"]],
  ["macotron.launcher", ["Inject extra launcher rows"]],
  ["macotron.usb", ["List devices; usb:changed"]],
  ["macotron.shortcuts", ["List and run Shortcuts.app"]],
  ["macotron.url", ["Custom schemes; open in an app or profile"]],
  ["macotron.keychain", ["get, set, delete, has"]],
  ["macotron.idle", ["Seconds idle; threshold; idle/active events"]],
  ["macotron.settings / checks", ["Open the plugin page; status rows"]],
];

const FILES = [
  { id: "AGENTS.md", path: "workdir/AGENTS.md", label: "AGENTS.md", group: "root" },
  { id: "README.md", path: "workdir/README.md", label: "README.md", group: "root" },
  { id: "demo-windows.js", path: "workdir/plugins/demo-windows.js", label: "demo-windows.js", group: "plugins" },
  { id: "demo-ai-chat.js", path: "workdir/plugins/demo-ai-chat.js", label: "demo-ai-chat.js", group: "plugins" },
  { id: "demo-weather.js", path: "workdir/plugins/demo-weather.js", label: "demo-weather.js", group: "plugins" },
  { id: "demo-battery.js", path: "workdir/plugins/demo-battery.js", label: "demo-battery.js", group: "plugins" },
  { id: "demo-fan.js", path: "workdir/plugins/demo-fan.js", label: "demo-fan.js", group: "plugins" },
  { id: "demo-now-playing.js", path: "workdir/plugins/demo-now-playing.js", label: "demo-now-playing.js", group: "plugins" },
  { id: "demo-meetings.js", path: "workdir/plugins/demo-meetings.js", label: "demo-meetings.js", group: "plugins" },
  { id: "demo-screen-ai-summary.js", path: "workdir/plugins/demo-screen-ai-summary.js", label: "demo-screen-ai-summary.js", group: "plugins" },
  { id: "demo-ocr.js", path: "workdir/plugins/demo-ocr.js", label: "demo-ocr.js", group: "plugins" },
  { id: "demo-file-search.js", path: "workdir/plugins/demo-file-search.js", label: "demo-file-search.js", group: "plugins" },
  { id: "demo-snippets.js", path: "workdir/plugins/demo-snippets.js", label: "demo-snippets.js", group: "plugins" },
  { id: "demo-calculator.js", path: "workdir/plugins/demo-calculator.js", label: "demo-calculator.js", group: "plugins" },
  { id: "demo-night-vision.js", path: "workdir/plugins/demo-night-vision.js", label: "demo-night-vision.js", group: "plugins" },
  { id: "demo-pomodoro.js", path: "workdir/plugins/demo-pomodoro.js", label: "demo-pomodoro.js", group: "plugins" },
  { id: "demo-clipboard-history.js", path: "workdir/plugins/demo-clipboard-history.js", label: "demo-clipboard-history.js", group: "plugins" },
];

const cache = new Map();

function esc(s) {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

function highlight(src, name) {
  const raw = esc(src);
  if (!name.endsWith(".js")) {
    return raw
      .replace(/^#.+$/gm, '<span class="tok-fn">$&</span>')
      .replace(/`[^`]+`/g, '<span class="tok-str">$&</span>');
  }
  const parts = [];
  const re = /(\/\/.*$|\/\*[\s\S]*?\*\/|`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/gm;
  let last = 0;
  let m;
  while ((m = re.exec(raw))) {
    parts.push(colorJS(raw.slice(last, m.index)));
    const t = m[0];
    const cls = t.startsWith("/") ? "tok-cmt" : "tok-str";
    parts.push(`<span class="${cls}">${t}</span>`);
    last = m.index + t.length;
  }
  parts.push(colorJS(raw.slice(last)));
  return parts.join("");
}

function colorJS(chunk) {
  return chunk
    .replace(/\b(const|let|var|function|return|if|else|async|await|new|typeof|true|false|null|undefined)\b/g, '<span class="tok-kw">$1</span>')
    .replace(/\b(macotron)\b/g, '<span class="tok-fn">$1</span>')
    .replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');
}

function renderCards(query) {
  const q = query.trim().toLowerCase();
  const hits = CARDS.filter(([t, d]) => !q || t.toLowerCase().includes(q) || d.toLowerCase().includes(q));
  const root = document.getElementById("cards");
  root.classList.toggle("empty-msg", hits.length === 0);
  root.replaceChildren(
    ...hits.map(([t, d]) => {
      const el = document.createElement("article");
      el.className = "card";
      el.innerHTML = `<h3>${esc(t)}</h3><p>${esc(d)}</p>`;
      return el;
    })
  );
}

function renderApis() {
  const root = document.getElementById("apis");
  root.replaceChildren(
    ...APIS.map(([title, items]) => {
      const el = document.createElement("article");
      el.innerHTML = `<h3>${esc(title)}</h3><ul>${items.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>`;
      return el;
    })
  );
}

function renderSidebar(current) {
  const nav = document.getElementById("sidebar");
  nav.replaceChildren();
  const addLabel = (text) => {
    const p = document.createElement("p");
    p.className = "side-label";
    p.textContent = text;
    nav.append(p);
  };
  addLabel("Folder");
  for (const f of FILES) {
    if (f.group === "plugins" && !nav.querySelector("[data-plugins]")) {
      addLabel("plugins");
      nav.lastElementChild.dataset.plugins = "1";
    }
    const b = document.createElement("button");
    b.type = "button";
    b.className = "side-btn";
    b.dataset.kind = f.label.endsWith(".js") ? "js" : "md";
    b.textContent = f.label;
    b.setAttribute("aria-current", f.id === current ? "true" : "false");
    b.addEventListener("click", () => openFile(f.id));
    nav.append(b);
  }
}

async function openFile(id) {
  const file = FILES.find((f) => f.id === id);
  if (!file) return;
  renderSidebar(id);
  document.getElementById("finder-title").textContent = file.label;
  const code = document.querySelector("#code code");
  if (!cache.has(id)) {
    code.textContent = "Loading...";
    const res = await fetch(file.path);
    cache.set(id, res.ok ? await res.text() : `Could not load ${file.path}`);
  }
  code.innerHTML = highlight(cache.get(id), file.label);
}

function currentTheme() {
  return localStorage.getItem("theme") || "system";
}

function applyTheme(mode) {
  if (mode === "light" || mode === "dark") document.documentElement.dataset.theme = mode;
  else delete document.documentElement.dataset.theme;
  localStorage.setItem("theme", mode);
  document.querySelectorAll("[data-theme-set]").forEach((btn) => {
    btn.setAttribute("aria-pressed", btn.dataset.themeSet === mode ? "true" : "false");
  });
}

function boot() {
  applyTheme(currentTheme());
  document.querySelector(".theme").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-theme-set]");
    if (btn) applyTheme(btn.dataset.themeSet);
  });
  renderCards("");
  renderApis();
  document.getElementById("q").addEventListener("input", (e) => renderCards(e.target.value));
  openFile("demo-windows.js");
}

boot();
