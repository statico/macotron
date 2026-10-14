// APIs: menubar.status, launcher.set, shell.run, url.open, fs.watch, notify.toast
macotron.plugin({
  title: "Screen Sharing",
  description: "Connect to saved Screen Sharing computers from the menu bar or the launcher.",
});

// The app keeps its connection list as a binary plist embedded in its prefs under `connectionsStore`.
const READ = "/usr/bin/defaults export com.apple.ScreenSharing - | /usr/bin/plutil -extract connectionsStore raw -o - - | /usr/bin/base64 -d | /usr/bin/plutil -extract connectionDetails json -o - -";
const PREFS_DIR = "~/Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences";

function connect(c) {
  const url = "vnc://" + (c.username ? encodeURIComponent(c.username) + "@" : "") + c.address + (c.port ? ":" + c.port : "");
  console.log("screen-sharing: connecting to", c.displayName, url);
  if (!macotron.url.open(url, "com.apple.ScreenSharing")) {
    console.error("screen-sharing: open failed for", url);
    macotron.notify.toast("Screen Sharing", "Couldn't open " + (c.displayName || c.address), { color: "error" });
  }
}

async function paint() {
  let menu;
  let conns = [];
  try {
    const res = await macotron.shell.run("/bin/sh", ["-c", READ]);
    if (res.exitCode !== 0) throw new Error(res.stderr.trim() || "exit " + res.exitCode);
    conns = Object.values(JSON.parse(res.stdout))
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
    { title: "Open Screen Sharing", onClick: () => macotron.shell.run("/usr/bin/open", ["-b", "com.apple.ScreenSharing"]) },
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
