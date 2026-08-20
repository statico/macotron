const opts = macotron.plugin({
    title: "Meetings",
    description: "Next calendar event in the menu bar.",
    options: {
        hours: {
            type: "number",
            label: "Look ahead (hours, at least rest of today)",
            default: 12,
        },
        hide: {
            type: "string",
            label: "Hide titles matching (one regex per line)",
            default: "personal\nOOO",
        },
    },
});

function patterns(text) {
    return String(text || "").split("\n").map((line) => line.trim()).filter(Boolean).flatMap((line) => {
        try {
            return [new RegExp(line, "i")];
        } catch (err) {
            return [];
        }
    });
}

function hidden(event, regs) {
    const text = [event.title, event.location, event.calendar].filter(Boolean).join(" ");
    return regs.some((re) => re.test(text));
}

function clip(s, n) {
    s = s || "";
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

function timeLabel(start, end) {
    const now = Date.now();
    if (start <= now && now < end) return "Now";
    const mins = Math.round((start - now) / 60000);
    if (mins <= 0) return "Now";
    if (mins < 60) return "in " + mins + "m";
    return new Date(start).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function joinURL(event) {
    const loc = String(event.location || "").trim();
    return /^https?:\/\//i.test(loc) ? loc : "";
}

function hoursUntilTomorrow() {
    const now = new Date();
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    return Math.max((end - now) / 3600000, 0.25);
}

function upcoming() {
    const regs = patterns(opts.hide);
    const configured = Number(opts.hours);
    const hours = configured > 0 ? Math.max(configured, hoursUntilTomorrow()) : hoursUntilTomorrow();
    return macotron.calendar.upcoming({ hours }).filter((event) => !hidden(event, regs));
}

function nextTimed(events) {
    const now = Date.now();
    return events.find((event) => !event.allDay && event.end > now) || null;
}

function openCalendar() {
    macotron.app.launch("com.apple.iCal");
}

function joinOrOpen(event) {
    const url = joinURL(event);
    if (url) macotron.url.open(url);
    else openCalendar();
}

function menu(events, next) {
    if (!events.length) {
        return [
            { title: "No upcoming events" },
            "-",
            { title: "Open Calendar", onClick: openCalendar },
        ];
    }
    const rows = [];
    const timed = events.filter((event) => !event.allDay);
    const allDay = events.filter((event) => event.allDay);
    for (const event of timed) {
        const mark = next && event.id === next.id ? "→ " : "";
        rows.push({
            title: mark + timeLabel(event.start, event.end) + "  " + (event.title || "Untitled"),
            onClick: () => joinOrOpen(event),
        });
    }
    if (allDay.length) {
        if (rows.length) rows.push("-");
        rows.push({ title: "All day" });
        for (const event of allDay) {
            rows.push({
                title: event.title || "Untitled",
                onClick: () => joinOrOpen(event),
            });
        }
    }
    rows.push("-", { title: "Open Calendar", onClick: openCalendar });
    return rows;
}

function paint() {
    const events = upcoming();
    const next = nextTimed(events);
    macotron.menubar.status("meetings", {
        title: next ? clip(next.title || "Untitled", 22) : "No meetings",
        subtitle: next ? timeLabel(next.start, next.end) : "",
        sfSymbol: next ? "calendar.badge.clock" : "calendar",
        secondary: true,
        minWidth: next ? 72 : undefined,
        menu: menu(events, next),
    });
}

paint();
macotron.every(30000, paint);

macotron.command("Next Meeting", "Show the next calendar event", () => {
    const next = nextTimed(upcoming());
    macotron.notify.toast(
        next ? next.title || "Untitled" : "No meetings",
        next ? timeLabel(next.start, next.end) : "Nothing in the next " + (opts.hours || 12) + " hours"
    );
});
