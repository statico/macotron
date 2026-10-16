// APIs: menubar.status, launcher.set, plist, app.launch, url.open, fs.watch, notify.toast
macotron.plugin({
  title: "Screen Sharing",
  description: "Connect to saved Screen Sharing computers from the menu bar or the launcher.",
});

const PREFS_DIR = "~/Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences";

// The app keeps its connection list as a binary plist embedded as Data in its prefs under `connectionsStore`.
function readConnections() {
  const prefs = macotron.plist.read(PREFS_DIR + "/com.apple.ScreenSharing.plist");
  // No prefs (or no store in them) means Screen Sharing has never saved a computer.
  if (!prefs?.connectionsStore) return {};
  const store = macotron.plist.parse({ base64: prefs.connectionsStore });
  if (!store) throw new Error("unreadable connectionsStore");
  return store.connectionDetails || {};
}

// The saved connection's type as the vnc:// query Screen Sharing parses (`quality`, not `displayType`, which it ignores and then saves the session back as Standard); without one it asks
// "High Performance or Standard?". displayType is {virtualDisplays: {numberOfDisplays}}, {remoteMacsDisplay: {}}
// or {compatibilityMode: {}}.
function typeQuery(displayType) {
  if (!displayType) return "";
  if (displayType.compatibilityMode) return "?quality=adaptive&numVirtualDisplays=0";
  // High Performance needs numVirtualDisplays >= 1; with 0 Screen Sharing falls back to Standard (saved entries can store 0).
  const n = Math.max(1, displayType.virtualDisplays?.numberOfDisplays ?? 0);
  return "?quality=high&numVirtualDisplays=" + n;
}

function connect(c) {
  const url = "vnc://" + (c.username ? encodeURIComponent(c.username) + "@" : "") + c.address + (c.port ? ":" + c.port : "")
    + typeQuery(c.displayConfiguration?.displayType);
  console.log("screen-sharing: connecting to", c.displayName, url);
  if (!macotron.url.open(url, "com.apple.ScreenSharing")) {
    console.error("screen-sharing: open failed for", url);
    macotron.notify.toast("Screen Sharing", "Couldn't open " + (c.displayName || c.address), { color: "error" });
  }
}

function paint() {
  let menu;
  let conns = [];
  try {
    conns = Object.values(readConnections())
      .map((d) => d.connectionParameters?.networkAddress?._0)
      .filter((c) => c?.address)
      .sort((a, b) => (a.displayName || a.address).localeCompare(b.displayName || b.address));
    console.log("screen-sharing: found", conns.length, "connections");
    menu = conns.map((c) => ({ title: c.displayName || c.address, onClick: () => connect(c) }));
    if (!menu.length) menu = [{ title: "No saved connections", dimmed: true }];
  } catch (e) {
    console.error("screen-sharing: read failed", e);
    menu = [{ title: "Can't read connections: " + (e.message || e), dimmed: true }];
  }
  menu.push(
    "-",
    { title: "Open Screen Sharing", onClick: () => macotron.app.launch("com.apple.ScreenSharing") },
    { title: "Refresh", onClick: paint },
  );
  macotron.launcher.set("screen-sharing", conns.map((c) => ({
    id: c.address + (c.port ? ":" + c.port : ""),
    title: c.displayName || c.address,
    subtitle: "Screen Sharing · " + c.address,
    app: "com.apple.ScreenSharing",
    onClick: () => connect(c),
  })));
  macotron.menubar.status("screen-sharing", { title: "", sfSymbol: "display.2", menu });
}

// The prefs folder only exists once Screen Sharing has run; without it the Refresh item still works.
try {
  macotron.fs.watch(PREFS_DIR, paint);
} catch (e) {
  console.error("screen-sharing: watch failed", e);
}
paint();
