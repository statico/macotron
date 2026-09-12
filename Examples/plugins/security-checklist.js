// APIs: command, shell.run, http.get, app.list, panel, notify

macotron.plugin({
    title: "Security Checklist Example",
    description: "Check FileVault, the firewall, System Integrity Protection, and app updates.",
});

async function run(cmd, args) {
    try {
        return await macotron.shell.run(cmd, args);
    } catch (err) {
        return { stdout: "", stderr: String(err), exitCode: 1 };
    }
}

// Shelling out once per app and then fetching a feed each is slow enough that
// it has to stay bounded, and the apps that are running are the ones worth
// worrying about anyway.
const APP_LIMIT = 12;

// Sparkle publishes newest-first, so the first <item> is the current release.
// Parsing an appcast with a regular expression is crude, but the alternative
// is an XML parser this host does not ship for four fields.
function newestAppcastVersion(xml) {
    const found = String(xml || "").match(/<item[\s>][\s\S]*?<\/item>/i);
    if (!found) return null;
    const item = found[0];

    const element = item.match(/<sparkle:shortVersionString>\s*([^<]+?)\s*<\/sparkle:shortVersionString>/i);
    if (element) return element[1];

    // Just as many feeds hang it off the enclosure as an attribute.
    const attribute = item.match(/sparkle:shortVersionString\s*=\s*"([^"]+)"/i);
    if (attribute) return attribute[1];

    // Older feeds only name the version in the title, as "Something 1.2.3".
    const title = item.match(/<title>[^<]*?(\d+(?:\.\d+)+)[^<]*<\/title>/i);
    return title ? title[1] : null;
}

// Compare dotted versions as numbers. A string comparison calls 1.10 older
// than 1.9, and telling someone their current app is out of date is worse
// than saying nothing at all.
function compareVersions(a, b) {
    const left = String(a).split(".");
    const right = String(b).split(".");
    for (let i = 0; i < Math.max(left.length, right.length); i++) {
        // Info.plist versions pick up build suffixes like "1.2.3b4". Take the
        // leading digits rather than letting parseInt hand back NaN.
        const na = parseInt(left[i], 10) || 0;
        const nb = parseInt(right[i], 10) || 0;
        if (na !== nb) return na > nb ? 1 : -1;
    }
    return 0;
}

async function plistValue(path, key) {
    const r = await run("/usr/bin/defaults", ["read", path + "/Contents/Info.plist", key]);
    // A key the bundle does not declare exits non-zero, which is an answer,
    // not an error.
    return r.exitCode === 0 ? String(r.stdout).trim() : "";
}

// app.list() names the running apps but not where they live, and Spotlight is
// the Apple-shipped way to turn a bundle identifier back into a path.
async function bundlePath(bundleID) {
    // The identifier goes into a query string, so refuse anything that is not
    // shaped like one rather than letting it close the quote.
    if (!/^[A-Za-z0-9.\-]+$/.test(String(bundleID))) return "";
    const r = await run("/usr/bin/mdfind", ["kMDItemCFBundleIdentifier == '" + bundleID + "'"]);
    return String(r.stdout).split("\n")[0].trim();
}

async function outdatedApps() {
    const out = [];
    for (const app of macotron.app.list().slice(0, APP_LIMIT)) {
        const path = await bundlePath(app.bundleID);
        if (!path) continue;

        // No appcast means the developer never published one to compare
        // against. Skip the app: guessing from a third-party catalog would
        // be both wrong more often and a dependency this host will not take.
        const feed = await plistValue(path, "SUFeedURL");
        if (!/^https?:\/\//i.test(feed)) continue;

        const version = await plistValue(path, "CFBundleShortVersionString");
        if (!version) continue;

        const res = await macotron.http.get(feed);
        // A failed request resolves with status 0. An unreachable feed is not
        // evidence that anything is out of date.
        if (res.status < 200 || res.status >= 300 || !res.body) continue;

        const latest = newestAppcastVersion(res.body);
        if (latest && compareVersions(version, latest) < 0) {
            out.push(app.name + " " + version + " → " + latest);
        }
    }
    return out;
}

macotron.command("Security Checklist", "Probe FileVault, firewall, SIP, and app updates", async () => {
    const fv = await run("/usr/bin/fdesetup", ["status"]);
    const fw = await run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]);
    const sip = await run("/usr/bin/csrutil", ["status"]);
    const gate = await run("/usr/sbin/spctl", ["--status"]);

    const items = [
        ["FileVault", /FileVault is On/i.test(fv.stdout), (fv.stdout || fv.stderr).trim()],
        ["Firewall", /enabled/i.test(fw.stdout), (fw.stdout || fw.stderr).trim()],
        ["SIP", /enabled/i.test(sip.stdout), (sip.stdout || sip.stderr).trim()],
        ["Gatekeeper", /assessments enabled/i.test(gate.stdout), (gate.stdout || gate.stderr).trim()],
    ];

    const rows = items.map(([name, ok, detail]) => {
        const mark = ok ? "OK" : "CHECK";
        return `<div><b>${name}</b> <span class="${ok ? "ok" : "bad"}">${mark}</span><div class="muted mono">${String(detail).replace(/[<>&]/g, "")}</div></div>`;
    }).join("");

    const id = macotron.panel.open({
        title: "Security Checklist",
        width: 420,
        height: 360,
        html: `<div class="grow scroll">${rows}
<div><b>App updates</b> <span class="muted mono" id="apps">checking…</span></div>
</div>
<button onclick="close()">Close</button>
<script>
  window.__macotronReceive = (msg) => {
    // textContent, so an app that named itself with a tag cannot write markup
    // into this panel.
    document.getElementById("apps").textContent = msg.apps;
  };
</script>`,
    });

    // The scan shells out per app and then waits on somebody else's web
    // server, so it fills itself in after the panel is already on screen
    // rather than holding the four local checks behind the network.
    outdatedApps()
        .then((list) => macotron.panel.postMessage(id, {
            apps: list.length ? list.join(", ") : "all current",
        }))
        .catch((err) => macotron.panel.postMessage(id, { apps: String(err) }));
});
