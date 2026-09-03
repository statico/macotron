// APIs: files, launcher.query, spotlight.search, shell.run, localStorage, command, checks, every, notify.toast

const opts = macotron.plugin({
    title: "File Search",
    description: "Find files and folders as you type in the launcher, from Macotron's own index.",
    help: "Open the launcher and type part of a file name — matching files appear "
        + "below the apps and commands, from an index Macotron keeps of the folders "
        + "in Search scopes. Two letters are enough; a query with a slash completes "
        + "as a path: each segment matches one level, ~ is home, and a trailing "
        + "slash lists a folder. Return opens the file, ⌘Return reveals it in "
        + "Finder, ⌥Return shows a Quick Look "
        + "preview, and ⌘C copies the path. Files you open climb the list; "
        + "\"Reset File Ranking\" puts them back, for one path or for all of them.",
    options: {
        searchScopes: {
            type: "text",
            label: "Search scopes",
            help: "One folder per line. ~ is home. iCloud Drive and cloud storage live under "
                + "~/Library, so they are listed here to escape the Library ignore.",
            default: "~\n/Applications\n~/Library/Mobile Documents/com~apple~CloudDocs\n~/Library/CloudStorage",
        },
        ignorePatterns: {
            type: "text",
            label: "Ignore patterns",
            help: "One glob per line, matched against each name and each path inside a scope.",
            // Spotlight hides ~/Library, and it holds keychains, cookies and app
            // state, so the whole folder is out; the cloud folders under it come
            // back in as scopes of their own.
            default: "node_modules\n*.tmp\ngo/pkg\nLibrary",
        },
        includeHidden: {
            type: "boolean",
            label: "Include hidden files",
            help: "Index names that start with a dot.",
            default: false,
        },
        useIgnoreFiles: {
            type: "boolean",
            label: "Honour ignore files",
            help: "Skip what .gitignore, .ignore and .macotronignore files exclude.",
            default: true,
        },
        contentSearch: {
            type: "boolean",
            label: "Search file contents",
            help: "Add files whose text Spotlight has indexed with the query, below the name matches.",
            default: false,
        },
        maxResults: {
            type: "number",
            label: "Result count",
            help: "How many files to show in the launcher.",
            default: 8,
        },
    },
});

const lines = (s) => String(s || "").split("\n").map((x) => x.trim()).filter(Boolean);
const roots = lines(opts.searchScopes);
const limit = Math.max(1, Number(opts.maxResults) || 8);

// What you open is the best evidence of what you meant, and the one signal
// no index can see. Opens live here, keyed by path: how often, and when.
const KEY = "file-search:opens:v2";
const OLD_KEY = "file-search:opens:v1";

let opens = (() => {
    try {
        // v1 stored bare counts. They keep their weight and start with no date.
        const old = JSON.parse(localStorage.getItem(OLD_KEY) || "null");
        if (old) {
            const migrated = {};
            for (const p of Object.keys(old)) migrated[p] = { count: Number(old[p]) || 0, last: 0 };
            localStorage.setItem(KEY, JSON.stringify(migrated));
            localStorage.removeItem(OLD_KEY);
            return migrated;
        }
        return JSON.parse(localStorage.getItem(KEY) || "{}");
    } catch (_) {
        return {};
    }
})();

const byRecency = (a, b) => (opens[b].last - opens[a].last) || (opens[b].count - opens[a].count);

// Only the newest 200 are kept, so years of opens cannot grow into a map that
// is parsed on every load.
const remember = () => {
    const keep = Object.keys(opens).sort(byRecency).slice(0, 200);
    if (keep.length < Object.keys(opens).length) {
        const trimmed = {};
        for (const p of keep) trimmed[p] = opens[p];
        opens = trimmed;
    }
    localStorage.setItem(KEY, JSON.stringify(opens));
};

const open = (path) => {
    const o = opens[path] || { count: 0, last: 0 };
    opens[path] = { count: o.count + 1, last: Date.now() };
    remember();
    macotron.shell.run("/usr/bin/open", [path]);
};

// Any home directory becomes ~ so the subtitle stays inside one row.
const short = (path) => path.replace(/^\/Users\/[^/]+\//, "~/");

const row = (path, isDir) => ({
    id: path,
    title: path.replace(/\/$/, "").split("/").pop() || path,
    subtitle: short(path),
    kind: isDir ? "Folder" : "File",
    path,
    onClick: () => open(path),
});

// A build without the indexer, or one that failed to start, still finds
// files: everything goes through Spotlight until status() says otherwise.
let available = false;
// The scopes as the indexer resolved them: absolute, so mdfind can take them.
let resolvedRoots = [];
let stopPolling = null;
const UNAVAILABLE = "Indexer unavailable, using Spotlight";

const withCommas = (n) => String(n).replace(/\B(?=(\d{3})+$)/g, ",");

async function refreshStatus() {
    const s = await macotron.files.status().catch(() => ({ available: false }));
    available = s.available !== false;
    if (available && s.roots && s.roots.length) resolvedRoots = s.roots;
    let message = UNAVAILABLE;
    if (available) message = s.indexing ? "Indexing…" : withCommas(s.entries || 0) + " files indexed";
    macotron.checks([{ title: "File index", ok: available, message }]);
    // Polling only runs while a build is in progress; the watcher covers the rest.
    if (available && s.indexing && !stopPolling) stopPolling = macotron.every(5000, refreshStatus);
    if (!s.indexing && stopPolling) {
        stopPolling();
        stopPolling = null;
    }
}

macotron.files.configure({
    roots,
    ignore: lines(opts.ignorePatterns),
    hidden: !!opts.includeHidden,
    ignoreFiles: !!opts.useIgnoreFiles,
}).then(refreshStatus, (e) => {
    // A bad glob is the user's to fix, so it goes on the plugin page, not in the log.
    macotron.checks([{ title: "File index", ok: false, message: String((e && e.message) || e) }]);
});

// Spotlight is the only content index on the Mac, so this reaches exactly
// what Spotlight has indexed: text it can read, in folders it is allowed to see.
async function contentHits(term) {
    // Same escapes as the host's Spotlight module: a stray * or ( would turn the query into a scan.
    const q = 'kMDItemTextContent == "' + term.replace(/[\\*?()'"]/g, "\\$&") + '"cd';
    // mdfind does not expand ~, so prefer the roots the indexer resolved;
    // before it has answered, absolute scopes are all there is to narrow by.
    const args = [];
    for (const r of resolvedRoots.length ? resolvedRoots : roots.filter((x) => x.startsWith("/"))) {
        args.push("-onlyin", r);
    }
    const r = await macotron.shell.run("/usr/bin/mdfind", args.concat(q)).catch(() => null);
    return r && r.exitCode === 0 ? r.stdout.split("\n").filter(Boolean).slice(0, 100) : [];
}

async function search(term) {
    let paths = [];
    let dirs = {};
    // Path completion lives in the Spotlight module, and so does everything
    // when the indexer is missing.
    const pathQuery = term.includes("/") || term === "~";
    if (available && !pathQuery) {
        // A rejection means the indexer is gone; Spotlight takes over until
        // status() sees it back.
        const hits = await macotron.files.search(term, { limit: 50 }).catch(() => null);
        if (hits) {
            for (const h of hits) {
                paths.push(h.path);
                if (h.isDir) dirs[h.path] = true;
            }
        } else {
            available = false;
            macotron.checks([{ title: "File index", ok: false, message: UNAVAILABLE }]);
        }
    }
    if (!available || pathQuery) {
        paths = ((await macotron.spotlight.search(term).catch(() => [])) || []).map((h) => h.path);
    }
    // Content matches cost an mdfind run, so they wait for a term worth one.
    if (opts.contentSearch && !pathQuery && term.length >= 3) {
        const seen = new Set(paths);
        for (const p of await contentHits(term)) if (!seen.has(p)) paths.push(p);
    }
    // Sort is stable, so files you have never opened keep the order the index
    // ranked them in and only the ones you have actually opened move.
    const count = (p) => (opens[p] ? opens[p].count : 0);
    return paths
        .sort((a, b) => count(b) - count(a))
        .slice(0, limit)
        .map((p) => row(p, !!dirs[p]));
}

macotron.launcher.query("file-search", async (query) => {
    const term = String(query || "").trim();
    // One letter matches most of the disk even with a local index — but a
    // slash means a path is being typed, and "~/" already says everything.
    if (term.length < 2 && !term.includes("/") && term !== "~") return [];
    return search(term);
}, {
    secondary: true,
    // Row ids are paths, so a shortcut bound to a row still works once the
    // search that produced it is long gone.
    run: (path) => open(path),
});

macotron.command("Reindex Files", "Drop the file index and walk the search scopes again.", async () => {
    if (!available) return macotron.notify.toast("Files", UNAVAILABLE);
    await macotron.files.reindex();
    macotron.notify.toast("Files", "Reindexing…");
    refreshStatus();
});

macotron.command(
    "Reset File Ranking",
    "Forget how often files were opened from the launcher.",
    (args) => {
        const path = String((args && args.path) || "").trim();
        if (path) {
            delete opens[path];
        } else {
            opens = {};
        }
        remember();
        macotron.notify.toast(path ? "Reset ranking for " + short(path) : "File ranking reset");
    },
    {
        arguments: [
            { name: "path", type: "text", placeholder: "Full path, or blank for every file" },
        ],
    }
);
