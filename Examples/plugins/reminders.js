macotron.plugin({
    title: "Reminders",
    description: "Next reminder in the menu bar.",
});

function clip(s, n) {
    s = s || "";
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function dueText(due) {
    if (due == null) return "";
    if (due < Date.now()) return "Overdue";
    return new Date(due).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

function paint() {
    const items = macotron.reminders.list().slice(0, 8);
    const next = items[0];
    const menu = items.map((item) => ({
        title: item.title,
        onClick: () => { macotron.reminders.complete(item.id); paint(); },
    }));
    if (menu.length) menu.push("-");
    menu.push({
        title: "Add…",
        onClick: () => {
            const title = prompt("New reminder");
            if (!title) return;
            macotron.reminders.add({ title });
            paint();
        },
    });
    macotron.menubar.status("reminders", {
        title: next ? clip(next.title, 22) : "Reminders",
        subtitle: next ? dueText(next.due) : "",
        sfSymbol: "checklist",
        secondary: true,
        menu,
    });
}

paint();
macotron.every(60_000, paint);
