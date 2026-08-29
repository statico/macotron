// APIs: launcher.query, spotlight.search, shell.run

macotron.plugin({
    title: "File Search",
    description: "Find files with Spotlight from the launcher.",
    help: "Open the launcher and type `f` (or `file`) then part of a name — `f budget.pdf`, "
        + "`file vacation`. Return opens the file, ⌘Return reveals it in Finder.",
});

const open = (path) => macotron.shell.run("/usr/bin/open", [path]);

// Any home directory becomes ~ so the subtitle stays inside one row.
const short = (path) => path.replace(/^\/Users\/[^/]+\//, "~/");

macotron.launcher.query("file-search", async (query) => {
    // An mdfind per keystroke of every query would bury apps under filenames,
    // so results only appear behind the prefix.
    const m = String(query || "").match(/^(?:f|file)\s+(.{2,})$/i);
    if (!m) return [];
    const hits = await macotron.spotlight.search(m[1].trim()).catch(() => []);
    return (hits || []).slice(0, 8).map((h) => ({
        id: h.path,
        title: h.name,
        subtitle: short(h.path),
        kind: "File",
        path: h.path,
        onClick: () => open(h.path),
    }));
}, {
    // Row ids are paths, so a shortcut bound to a row still works once the
    // search that produced it is long gone.
    run: (path) => open(path),
});
