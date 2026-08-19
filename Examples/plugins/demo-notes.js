macotron.plugin({
    title: "Notes",
    description: "Apple Notes in the launcher.",
});

function paint() {
    const notes = macotron.notes.list();
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
macotron.every(60000, paint);
