// APIs: launcher.query, spotlight.search, shell.run, localStorage, command, notify.toast

macotron.plugin({
    title: "File Search",
    description: "Find files with Spotlight as you type in the launcher.",
    help: "Open the launcher and type part of a file name — matching files appear "
        + "below the apps and commands. A few letters can span folder names, and a "
        + "query with a slash completes as a path: each segment matches one level, "
        + "~ is home, and a trailing slash lists a folder. Return opens the file, "
        + "⌘Return reveals it in Finder. Files you open climb the list; \"Reset File "
        + "Ranking\" puts them back, for one path or for all of them.",
});

// What you open is the best evidence of what you meant, and the one signal
// Spotlight cannot see. Counts live here, keyed by path.
const KEY = "file-search:opens:v1";

let opens = (() => {
    try {
        return JSON.parse(localStorage.getItem(KEY) || "{}");
    } catch (_) {
        return {};
    }
})();

const remember = () => localStorage.setItem(KEY, JSON.stringify(opens));

const open = (path) => {
    opens[path] = (opens[path] || 0) + 1;
    remember();
    macotron.shell.run("/usr/bin/open", [path]);
};

// Any home directory becomes ~ so the subtitle stays inside one row.
const short = (path) => path.replace(/^\/Users\/[^/]+\//, "~/");

macotron.launcher.query("file-search", async (query) => {
    // Two letters match half the disk, so the search waits for a third — but
    // a slash means a path is being typed, and "~/" already says everything.
    const term = String(query || "").trim();
    if (term.length < 3 && !term.includes("/") && term !== "~") return [];
    const hits = await macotron.spotlight.search(term).catch(() => []);
    // Sort is stable, so files you have never opened keep the order the host
    // ranked them in and only the ones you have actually opened move.
    return (hits || [])
        .slice()
        .sort((a, b) => (opens[b.path] || 0) - (opens[a.path] || 0))
        .slice(0, 8)
        .map((h) => ({
            id: h.path,
            title: h.name,
            subtitle: short(h.path),
            kind: "File",
            path: h.path,
            onClick: () => open(h.path),
        }));
}, {
    secondary: true,
    // Row ids are paths, so a shortcut bound to a row still works once the
    // search that produced it is long gone.
    run: (path) => open(path),
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
