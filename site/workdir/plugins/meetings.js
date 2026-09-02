const opts = macotron.plugin({
    title: "Meetings Menu",
    description: "Show your next calendar event in the menu bar.",
    permissions: ["calendar"],
    options: {
        hours: {
            type: "number",
            label: "Look ahead",
            help: "Hours of calendar to show. The rest of today is always included.",
            default: 12,
        },
        hide: {
            type: "text",
            label: "Hide titles",
            help: "One regular expression per line. Events whose title matches are skipped.",
            default: "personal\nOOO",
        },
        time: {
            type: "dropdown",
            label: "Show time as",
            default: "relative",
            choices: [
                { value: "relative", label: "Relative (in 1h 15m)" },
                { value: "start", label: "Start time (1:15 PM)" },
            ],
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

const hour12 = macotron.system.locale().hour12;

// QuickJS has no Intl, so the clock is built by hand from the system setting.
function clockLabel(at) {
    const d = new Date(at);
    const mins = d.getMinutes();
    let hours = d.getHours();
    const suffix = hour12 ? (hours < 12 ? " AM" : " PM") : "";
    if (hour12) hours = hours % 12 || 12;
    return hours + (mins ? ":" + String(mins).padStart(2, "0") : "") + suffix;
}

function relativeLabel(start) {
    const mins = Math.round((start - Date.now()) / 60000);
    if (mins < 1) return "Now";
    if (mins < 60) return "in " + mins + "m";
    const rest = mins % 60;
    return "in " + Math.floor(mins / 60) + "h" + (rest ? " " + rest + "m" : "");
}

function timeLabel(start) {
    const now = Date.now();
    if (start <= now) return "Now";
    return opts.time === "start" ? clockLabel(start) : relativeLabel(start);
}

function hoursUntilTomorrow() {
    const now = new Date();
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    return Math.max((end - now) / 3600000, 0.25);
}

async function upcoming() {
    const regs = patterns(opts.hide);
    const configured = Number(opts.hours);
    const hours = configured > 0 ? Math.max(configured, hoursUntilTomorrow()) : hoursUntilTomorrow();
    const events = await macotron.calendar.upcoming({ hours });
    // Sort defensively: an older host hands the list back in EventKit's
    // undefined order, and both the title and the menu assume soonest-first.
    return events.filter((event) => !hidden(event, regs)).sort((a, b) => a.start - b.start);
}

function nextTimed(events) {
    const now = Date.now();
    return events.find((event) => !event.allDay && event.end > now) || null;
}

function openCalendar() {
    macotron.app.launch("com.apple.iCal");
}

function joinOrOpen(event) {
    const url = event.url || "";
    if (url) macotron.url.open(url);
    else openCalendar();
}

function menu(events, next) {
    if (!events.length) {
        return [
            { title: "No meetings" },
            "-",
            { title: "Refresh", onClick: paint },
            { title: "Open Calendar", onClick: openCalendar },
        ];
    }
    const rows = [];
    const timed = events.filter((event) => !event.allDay);
    const allDay = events.filter((event) => event.allDay);
    for (const event of timed) {
        const mark = next && event.id === next.id ? "→ " : "";
        rows.push({
            title: mark + timeLabel(event.start) + "  " + (event.title || "Untitled"),
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
    rows.push("-", { title: "Refresh", onClick: paint }, { title: "Open Calendar", onClick: openCalendar });
    return rows;
}

let lastEvents = [];

async function paint() {
    try {
        lastEvents = await upcoming();
    } catch (err) {
        // Keep the last fetch; the repaint below still advances the clock.
    }
    // Even on a stale fetch, a meeting that has ended must drop out.
    const events = lastEvents.filter((event) => event.end > Date.now());
    const next = nextTimed(events);
    macotron.menubar.status("meetings", {
        title: next ? clip(next.title || "Untitled", 22) : "",
        subtitle: next ? timeLabel(next.start) : "",
        sfSymbol: next ? "calendar.badge.clock" : "calendar",
        secondary: true,
        minWidth: next ? 72 : undefined,
        menu: menu(events, next),
    });
}

paint();
macotron.every(30000, paint);

macotron.command("Next Meeting", "Show the next calendar event", async () => {
    const next = nextTimed(await upcoming());
    macotron.notify.toast(
        next ? next.title || "Untitled" : "No meetings",
        next ? timeLabel(next.start) : "Nothing in the next " + (opts.hours || 12) + " hours"
    );
});
