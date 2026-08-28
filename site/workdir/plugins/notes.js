macotron.plugin({
    title: "Notes Search",
    description: "Search Apple Notes from the launcher.",
});

async function paint() {
    const notes = await macotron.notes.list();
    macotron.launcher.set(
        "notes",
        notes.map((n) => ({
            id: n.id,
            title: n.title || "Untitled",
            subtitle: n.folder || "",
            app: "com.apple.Notes",
            kind: "Note",
            onClick: () => macotron.notes.open(n.id),
        }))
    );
}

paint();
// Every minute is a lot of Apple Events for a library with thousands of notes,
// and note titles do not change that fast.
macotron.every(300000, paint);
