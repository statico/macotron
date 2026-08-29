// APIs: launcher.query, spotlight.search, shell.run

macotron.plugin({
    title: "File Search",
    description: "Find files with Spotlight as you type in the launcher.",
    help: "Open the launcher and type part of a file name — matching files appear "
        + "below the apps and commands. Return opens the file, ⌘Return reveals it in Finder.",
});

const open = (path) => macotron.shell.run("/usr/bin/open", [path]);

// Any home directory becomes ~ so the subtitle stays inside one row.
const short = (path) => path.replace(/^\/Users\/[^/]+\//, "~/");

macotron.launcher.query("file-search", async (query) => {
    // Two letters match half the disk, so the search waits for a third.
    const term = String(query || "").trim();
    if (term.length < 3) return [];
    const hits = await macotron.spotlight.search(term).catch(() => []);
    return (hits || []).slice(0, 8).map((h) => ({
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
