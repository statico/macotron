const CARDS = [
  ["Launcher", [
    ["Quick launcher", "Cmd-Space style launcher for apps and commands."],
    ["Fuzzy search", "Type a few letters. Matches rank as you go."],
    ["Starred rows", "Pin launcher items with ⌘S so they show on open."],
    ["Command shortcuts", "Assign a key to any launcher command."],
    ["Command args", "Text, number, and dropdown prompts."],
    ["Launcher rows", "Plugins inject extra results."],
    ["Contacts search", "Names, emails, and phones as you type."],
    ["Web search", "Google, Wikipedia, Maps, YouTube, GitHub, Define."],
    ["Global hotkeys", "Carbon hotkeys, overridable in Settings."],
    ["Show Hotkeys", "Overlay of every bound combo."],
  ]],
  ["Windows", [
    ["Tile windows", "Halves, corners, center, or another display."],
    ["Drag-to-snap", "Pull a window to an edge or corner to tile."],
    ["Window grid", "Drag a cell to place the focused window."],
    ["Placement preview", "Ghost the destination before you commit."],
    ["Save layouts", "Snapshot frames and restore them later."],
    ["Switch windows", "Pick an open window by name and raise it."],
    ["Option-Tab switcher", "Hold Option and press Tab to flip windows."],
    ["Minimize / close", "Drive window chrome from a script."],
    ["Fullscreen", "Toggle native fullscreen on the focused window."],
    ["Window events", "React when a window is created or focused."],
    ["Move by frame", "Set exact pixels or display fractions."],
    ["Spaces", "List Mission Control desktops."],
    ["Switch desktop", "Go by number, id, or display."],
    ["Move to space", "SkyLight when SIP allows it."],
    ["Trackpad swipe", "Three-finger swipe tiles the focused window."],
  ]],
  ["Interface", [
    ["Menu bar extras", "Icons, two-line text, click menus beside Macotron."],
    ["Sparklines", "CPU or any series as a tiny menu-bar graph."],
    ["Icon tint", "Recolor the Macotron glyph from a plugin."],
    ["System banners", "UserNotifications from a one-liner."],
    ["HUD toasts", "One-line overlay under the cursor."],
    ["HTML panels", "Small WKWebView windows for custom UI."],
    ["Liquid Glass", "Translucent Tahoe panels, regular or clear."],
    ["HUD blur panels", "glass: translucent for a Control Center look."],
    ["Frameless panels", "No title bar. Escape closes."],
    ["Close on blur", "Panel goes away when it loses key focus."],
    ["Blocking dialogs", "alert, confirm, and prompt. Same as the browser."],
  ]],
  ["Screen & clipboard", [
    ["Screenshot", "Full display PNG, or drag a rectangle."],
    ["Color picker", "System magnifier eyedropper, hex plus RGB."],
    ["OCR", "Read text from a file or a screenshot."],
    ["QR scan", "Camera or a screen selection. First payload wins."],
    ["QR show", "Float a generated code in a window."],
    ["Spotlight search", "Folder and kind filters from plugin code."],
    ["Clipboard text", "Get and set the pasteboard."],
    ["Clipboard images", "Push a PNG onto the pasteboard."],
    ["Clipboard history", "Browse, paste, or drop old clips."],
    ["Snippets", "Abbreviation expansion as you type."],
    ["Plain paste", "Command-V strips to public.utf8-plain-text."],
    ["Markdown preview", "Render clipboard markdown in a glass panel."],
  ]],
  ["Display", [
    ["Dark mode", "Read and set system appearance."],
    ["Brightness", "Get and set display brightness."],
    ["XDR", "Toggle the extra-bright range."],
    ["Gamma LUT", "Per-channel white and black points."],
    ["Night vision", "Red-only gamma for dark rooms."],
    ["Extra dark", "Dim below the hardware minimum."],
    ["Invert display", "Swap white and black in the LUT."],
    ["Night Shift", "On/off and strength from a plugin."],
    ["True Tone", "Toggle when the private API is present."],
    ["Grayscale", "Force the display to gray."],
    ["Display list", "Frames, scale, serial, millimeters."],
    ["Display events", "Add, remove, move, mirror, mode."],
  ]],
  ["System", [
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
    ["Focus status", "Whether a Focus mode is on."],
    ["Idle time", "Seconds since the last HID event."],
    ["Idle hooks", "system:idle and system:active callbacks."],
    ["Locale", "Language, region, metric vs US units."],
    ["USB", "Name, vendor, attach and detach."],
    ["HID devices", "List, open, feature and input reports."],
    ["Time Machine", "Backup percent in the menu bar."],
  ]],
  ["Power", [
    ["Keep awake", "IOPM assertion so the Mac stays up."],
    ["Lock screen", "Lock now from a hotkey."],
    ["Sleep", "Put the machine to sleep."],
    ["Display sleep", "Blank the screens only."],
    ["Screensaver", "Start the saver from a script."],
    ["Log out / restart", "Or shut down. Same as the Apple menu."],
    ["Sleep events", "Hear system:sleep, wake, lock, unlock."],
  ]],
  ["Network", [
    ["Wi-Fi", "SSID, on/off, and interface IPs."],
    ["Bluetooth", "Radio toggle plus connected devices."],
    ["Device batteries", "Percent on paired Bluetooth hardware."],
    ["AirDrop", "Off, Contacts Only, or Everyone."],
    ["Network bytes", "Interface counters in and out."],
    ["Ping", "Round-trip via /sbin/ping."],
    ["HTTP", "GET/POST/PUT/DELETE from plugins."],
    ["Bonjour", "Browse mDNS services on the LAN."],
    ["UDP", "Send and listen on IPv4."],
  ]],
  ["Input", [
    ["Post clicks", "HID click at a Cocoa point."],
    ["Post keys", "Key downs with modifier flags."],
    ["Unicode type", "Paste characters the OS will type."],
    ["Scroll", "Pixel or line scroll events."],
    ["HID tap", "Listen, and swallow events if you want."],
    ["Mouse warp", "Move the cursor. Read buttons."],
    ["Hyper key", "Caps Lock or Fn as ⌘⇧⌃⌥ while held."],
    ["Gestures", "Swipe, magnify, and rotate from a tap."],
  ]],
  ["Apps", [
    ["Launch apps", "Open by bundle ID via Launch Services."],
    ["Switch apps", "Bring a running app forward."],
    ["Hide / quit", "Hide or terminate by bundle ID."],
    ["App menus", "Choose File → New from a script."],
    ["App events", "activated, launched, terminated."],
    ["Frontmost app", "React when the user switches focus."],
    ["Open in browser", "Pick Safari, a profile, or another app."],
    ["URL schemes", "Register macotron:// handlers."],
    ["Shortcuts.app", "List and run user shortcuts."],
    ["Dock badges", "Unread counts from Dock tiles."],
    ["Empty Trash", "From the Eject menu, Finder-style."],
  ]],
  ["Audio & media", [
    ["Audio devices", "List inputs and outputs."],
    ["Default output", "Cycle speakers or a USB DAC."],
    ["Volume", "0 to 1 on the system or a device."],
    ["Mute", "Toggle mute without touching volume."],
    ["Mic mute", "Mute the input from the menu bar."],
    ["Record", "Capture the microphone to a file."],
    ["Now Playing", "Title, artist, artwork, play/pause, skip."],
    ["Headphone pause", "Pause when the output device unplugs."],
  ]],
  ["Home & people", [
    ["Calendar", "Upcoming events for the next N hours."],
    ["Meetings", "Next event in the menu bar."],
    ["Meeting overlay", "Fullscreen join card 60s before, with QR."],
    ["Reminders", "List, add, and complete from a plugin."],
    ["Notes", "List Apple Notes and open one."],
    ["Contacts", "Search names, emails, phones."],
    ["HomeKit", "Homes, accessories, on/off and values."],
    ["World clock", "A few cities in the menu bar."],
  ]],
  ["Devices", [
    ["Camera list", "Built-in and USB cameras."],
    ["Camera preview", "Live panel, then a JPEG snapshot."],
    ["Apple TV", "Browse the LAN and send remote keys."],
    ["Share sheet", "Text, files, or a URL."],
    ["AirDrop", "Push paths through sharingd."],
  ]],
  ["Files & shell", [
    ["Read files", "Text or base64 bytes. ~ expands."],
    ["Write files", "Overwrite a path from a plugin."],
    ["Rename", "Atomic rename; fails if the dest exists."],
    ["Watch files", "FSEvents callback on change."],
    ["Spotlight kind", "folder and kind on mdfind-style search."],
    ["Shell", "Allowlisted Apple tools with a prompt."],
    ["Keychain", "Secrets that never hit settings.json."],
  ]],
  ["AI", [
    ["Apple Intelligence", "On-device Foundation Models."],
    ["Claude", "Anthropic chat and streaming."],
    ["Gemini", "Google models from a plugin."],
    ["OpenAI", "Same chat/stream shape."],
    ["Token stream", "Push chunks into a panel as they arrive."],
    ["Translate", "Selected text through the on-device model."],
  ]],
  ["Accessibility", [
    ["Focused element", "Role, title, value, and frame."],
    ["Selected text", "Whatever the focused field has highlighted."],
    ["AX tree", "Children, parent, find, press, setValue."],
  ]],
  ["Runtime", [
    ["Hot reload", "Save a .js file. The host reloads it."],
    ["QuickJS", "Embedded engine, bytecode cache."],
    ["ES modules", "import/export with a custom loader."],
    ["localStorage", "JSON store in the workdir."],
    ["every / at", "Interval or wall-clock jobs. Reload cancels them."],
    ["Git workdir", "Optional git init. Agents commit."],
    ["Stock Mac", "No Homebrew, npm, or extra binaries."],
    ["Settings UI", "Per-plugin page, shortcuts, checks."],
    ["Plugin options", "Text, toggles, dropdowns, files, keys."],
    ["Placeholders", "Live hints such as the current locale."],
    ["Password options", "Keychain-backed fields in Settings."],
    ["Plugin checks", "Orange warning when something is blocked."],
    ["First-run wizard", "Pick a folder. Seed README once."],
    ["AGENTS.md", "App-owned instructions for coding agents."],
    ["Community plugins", "GitHub topic macotron-plugin."],
    ["Direct download", "No App Store. Optional Homebrew cask."],
  ]],
  ["Featured plugins", [
    ["Calculator", "Evaluate an expression as you type."],
    ["Clipboard History", "Search recent clips from the launcher."],
    ["File Search", "Spotlight results in the launcher."],
    ["Lock Screen", "Lock this Mac from the launcher."],
    ["Meetings", "Next calendar event in the menu bar."],
    ["Notes", "Search Apple Notes from the launcher."],
    ["Snippets", "Text expansions from the launcher."],
    ["Weather", "Current weather in the menu bar."],
    ["Window Grid", "Drag a grid to place the focused window."],
    ["Windows", "Tile with the keyboard or snap by dragging."],
  ]],
  ["Built-in plugins", [
    ["Apple TV", "Remote for Apple TVs on the LAN."],
    ["Bluetooth", "Paired device batteries in the menu bar."],
    ["Contacts", "Search contacts from the launcher."],
    ["HomeKit", "Home accessories in the menu bar."],
    ["Hyper Key", "Hold Caps Lock as Hyper (⌘⇧⌃⌥)."],
    ["Mic Mute", "Mute the input from the menu bar."],
    ["Network Path", "Throughput and ping in the menu bar."],
    ["QR Code", "Scan from the screen or camera, or show one."],
    ["Record", "Microphone capture and camera preview."],
    ["Reminders", "Next reminder in the menu bar."],
    ["Share", "Share sheet and AirDrop from a command."],
    ["Time Machine", "Backup progress in the menu bar."],
    ["Translate", "Selected text through the on-device model."],
    ["Web Search", "Search the web or look up a word."],
    ["World Clock", "Times in the menu bar for a few cities."],
    ["Gestures", "Three-finger swipe tiles the focused window."],
    ["Layouts", "Save and restore the Work window layout."],
    ["Meeting Overlay", "Fullscreen join card with a QR."],
    ["Plain Paste", "Command-V pastes plain text only."],
    ["Window Switcher", "Hold Option and press Tab."],
  ]],
  ["More plugins", [
    ["AI Chat", "On-device model, Claude, or Gemini."],
    ["Appearance", "Toggle system light and dark mode."],
    ["Audio", "Cycle the default output device."],
    ["Batch Rename", "Prefix today's Downloads with the date."],
    ["Battery", "Charge level and time remaining."],
    ["Brightness", "Dim or brighten from the keyboard."],
    ["Browser Picker", "Unknown hosts show a picker."],
    ["Calendar", "Upcoming events."],
    ["Clipboard Images", "Count and re-paste image clips."],
    ["Color Picker", "System magnifier, hex plus RGB."],
    ["CPU Graph", "Usage sparkline in the menu bar."],
    ["Date Stamp", "Copy the current ISO-8601 timestamp."],
    ["Dev Utils", "UUID, hashes, Base64, JWT peek."],
    ["Eject", "Eject volumes, or empty the Trash."],
    ["Fan", "Hold a fan-speed floor from the menu bar."],
    ["Frontmost App", "Track the last app that became active."],
    ["Headphone Pause", "Pause media when headphones unplug."],
    ["HEIC to JPEG", "sips conversion on a stock Mac."],
    ["HID", "List HID devices attached to this Mac."],
    ["Icon Rainbow", "Cycle the menu bar glyph."],
    ["Idle", "Notify when the Mac goes idle or wakes."],
    ["Lorem Ipsum", "Generate placeholder text."],
    ["Markdown", "Preview clipboard markdown."],
    ["Now Playing", "Album art and track info."],
    ["OCR", "Select a screen area and copy the text."],
    ["Pomodoro", "A 25-minute focus timer."],
    ["Present Mode", "Hide desktop icons for a talk."],
    ["Profiles", "Light mode at home, dark mode at work."],
    ["Regex Workbench", "Test a pattern against a haystack."],
    ["Browser Picker", "Route links by host or pattern."],
    ["Screen Effects", "Night vision, extra dark, Night Shift."],
    ["Screen Summary", "Summarize a selection with Claude."],
    ["Screenshot Rename", "OCR the latest Desktop capture."],
    ["Security Checklist", "FileVault, firewall, SIP."],
    ["Shortcuts", "Run Shortcuts.app from the launcher."],
    ["Spaces", "Jump to the next Mission Control desktop."],
    ["Stay Awake", "Prevent sleep from the menu bar."],
    ["Storage", "Folder sizes in your home folder."],
    ["System Metrics", "CPU and GPU in the menu bar."],
    ["System Settings", "Search Settings panes from the launcher."],
    ["USB", "Toast when a device is plugged in."],
    ["Wi-Fi", "Toggle Wi-Fi, Bluetooth, and AirDrop."],
  ]],
];

const APIS = [
  ["macotron.window", [
    "List, focus, minimize, close, fullscreen",
    "move / moveToFraction / previewFraction",
    "restore saved frames",
    "Drag-to-edge snap maps",
    "window:created, window:focused",
  ]],
  ["macotron.keyboard", [
    "Global hotkeys with Settings override",
    "Modifier flags (cmd, opt, fn, ...)",
    "setHyperKey: caps or fn",
  ]],
  ["macotron.event / mouse", [
    "Post click, key, unicode, scroll",
    "HID tap; return false to swallow",
    "Swipe, magnify, rotate",
    "Cursor location, warp, buttons",
  ]],
  ["macotron.display", [
    "List frames, scale, serial, mm",
    "Brightness and XDR",
    "Gamma LUT, restore ColorSync",
    "Night Shift, True Tone, grayscale",
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
    "Lock, sleep, display sleep, screensaver",
    "Log out, restart, shutdown",
    "system:sleep, wake, lock, unlock",
  ]],
  ["macotron.audio", [
    "Devices, default in/out",
    "Volume and mute, including the mic",
    "record / stopRecord",
    "audio:changed",
  ]],
  ["macotron.network", [
    "Wi-Fi SSID and radio",
    "Bluetooth devices and batteries",
    "AirDrop mode, interface IPs",
    "counters and ping",
  ]],
  ["macotron.bonjour", ["Browse mDNS; timeout in seconds"]],
  ["macotron.udp", ["send, listen, unlisten; udp:message"]],
  ["macotron.appletv", ["list on the LAN; send remote keys"]],
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
  ["macotron.qr", [
    "detect from image or path",
    "scan camera or screenshot",
    "image / show a generated code",
  ]],
  ["macotron.clipboard", [
    "Text, images, UTIs",
    "History, paste, remove",
    "setPastePlain for Command-V",
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
    "closeOnBlur, fullscreen, qr",
    "postMessage / onMessage",
  ]],
  ["macotron.menubar", [
    "Menu rows and extra status items",
    "SF Symbols, images, two-line text",
    "sparkline / svg",
    "setIcon / setIconColor / setTitle",
  ]],
  ["macotron.notify", ["System banners and HUD toasts"]],
  ["macotron.media", ["Now Playing snapshot, play/pause, skip"]],
  ["macotron.calendar", ["Upcoming events with times and location"]],
  ["macotron.reminders", ["list, add, complete"]],
  ["macotron.notes", ["List and open Apple Notes"]],
  ["macotron.contacts", ["List and search"]],
  ["macotron.homekit", ["homes, accessories, set on/value"]],
  ["macotron.dock", ["Badge counts from Dock tiles"]],
  ["macotron.ax", ["focused, selectedText, find, press"]],
  ["macotron.camera", ["list, preview, snapshot"]],
  ["macotron.share", ["Share sheet and AirDrop"]],
  ["macotron.hid", ["list, open, reports, hid:input"]],
  ["macotron.spotlight", ["Search by query, folder, kind"]],
  ["macotron.launcher", ["Inject extra launcher rows"]],
  ["macotron.usb", ["List devices; usb:changed"]],
  ["macotron.shortcuts", ["List and run Shortcuts.app"]],
  ["macotron.url", ["Custom schemes; open in an app or profile"]],
  ["macotron.keychain", ["get, set, delete, has"]],
  ["macotron.idle", ["Seconds idle; threshold; idle/active events"]],
  ["macotron.every / at", ["Interval or wall-clock; weekday filter"]],
  ["alert / confirm / prompt", ["Blocking NSAlert sheets"]],
  ["macotron.settings / checks", ["Open the plugin page; status rows"]],
];

const FEATURED = [
  "calculator.js",
  "clipboard-history.js",
  "file-search.js",
  "lock-screen.js",
  "meetings.js",
  "notes.js",
  "snippets.js",
  "system-settings.js",
  "weather.js",
  "window-grid.js",
  "windows.js",
];

function pluginEntry(name, group) {
  return {
    id: name,
    path: "workdir/plugins/" + name,
    label: name,
    group,
  };
}

// `make site` copies Examples/plugins into workdir/plugins and writes the
// manifest, so this list cannot drift from what the repo actually ships.
const FILES = [
  { id: "AGENTS.md", path: "workdir/AGENTS.md", label: "AGENTS.md", group: "root" },
  { id: "README.md", path: "workdir/README.md", label: "README.md", group: "root" },
];

async function loadFiles() {
  const res = await fetch("workdir/plugins/index.json");
  const names = res.ok ? await res.json() : FEATURED;
  FILES.push(
    ...FEATURED.filter((n) => names.includes(n)).map((n) => pluginEntry(n, "featured")),
    ...names.filter((n) => !FEATURED.includes(n)).map((n) => pluginEntry(n, "plugins"))
  );
}

const cache = new Map();

function esc(s) {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

function cardHTML([t, d]) {
  return `<article class="card"><b>${esc(t)}</b><span>${esc(d)}</span></article>`;
}

function renderCards(query) {
  const q = query.trim().toLowerCase();
  const match = ([t, d]) => !q || t.toLowerCase().includes(q) || d.toLowerCase().includes(q);
  const groups = CARDS
    .map(([group, items]) => [group, group.toLowerCase().includes(q) ? items : items.filter(match)])
    .filter(([, items]) => items.length);
  const root = document.getElementById("cards");
  root.classList.toggle("empty-msg", groups.length === 0);
  root.replaceChildren(
    ...groups.map(([group, items]) => {
      const el = document.createElement("section");
      el.className = "group";
      el.innerHTML =
        `<h3>${esc(group)}</h3><div class="group-items">` +
        items.map(cardHTML).join("") +
        `</div>`;
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
  const addLabel = (text, key) => {
    const p = document.createElement("p");
    p.className = "side-label";
    p.textContent = text;
    if (key) p.dataset[key] = "1";
    nav.append(p);
  };
  addLabel("Folder");
  for (const f of FILES) {
    if (f.group === "featured" && !nav.querySelector("[data-featured]")) {
      addLabel("Featured", "featured");
    }
    if (f.group === "plugins" && !nav.querySelector("[data-plugins]")) {
      addLabel("plugins", "plugins");
    }
    const b = document.createElement("button");
    b.type = "button";
    b.className = "side-btn";
    b.dataset.kind = f.label.endsWith(".js") ? "js" : "md";
    b.textContent = f.label;
    if (f.id === current) b.setAttribute("aria-current", "true");
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
  code.className = file.label.endsWith(".js") ? "language-javascript" : "language-markdown";
  if (!cache.has(id)) {
    code.textContent = "Loading...";
    const res = await fetch(file.path);
    cache.set(id, res.ok ? await res.text() : `Could not load ${file.path}`);
  }
  code.textContent = cache.get(id);
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

function refresh() {
  renderCards(document.getElementById("q").value);
}

async function boot() {
  applyTheme(currentTheme());
  await loadFiles();
  document.querySelector(".theme").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-theme-set]");
    if (btn) applyTheme(btn.dataset.themeSet);
  });
  document.getElementById("q").addEventListener("input", refresh);
  refresh();
  renderApis();
  openFile("windows.js");
}

boot();
