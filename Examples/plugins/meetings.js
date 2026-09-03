const opts = macotron.plugin({
    title: "Meetings",
    description: "Show your next calendar event in the menu bar, with an optional full-screen overlay when a meeting starts.",
    permissions: ["calendar"],
    options: {
        calendars: {
            type: "calendars",
            label: "Calendars",
            help: "Only events from the checked calendars are shown. Check none to show every calendar.",
            default: [],
        },
        hours: {
            type: "number",
            label: "Look ahead",
            help: "Hours of calendar to show. The rest of today is always included.",
            default: 12,
        },
        hide: {
            type: "text",
            label: "Hide titles",
            help: "One regular expression per line. Events whose title, location, or calendar matches are skipped.",
            default: "ooo|vacation",
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
        overlay: {
            type: "boolean",
            label: "Meeting overlay",
            help: "Show a full-screen overlay when a meeting starts, with a QR code to join.",
            default: true,
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
    const events = await macotron.calendar.upcoming({ hours, calendars: opts.calendars });
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

// ---- Overlay: full-screen "meeting starting" panel with a QR code to join.

const KEY = "meetings.overlay-shown";

// Dismissals outlive a reload: without this, editing any plugin while a
// meeting is starting puts the overlay back up for one already waved away.
// Events are keyed by their end time so the list prunes itself.
const shown = new Map(Object.entries(JSON.parse(localStorage.getItem(KEY) || "{}")));

function remember(id, until) {
    shown.set(id, until);
    const now = Date.now();
    for (const [key, at] of shown) {
        if (at < now) shown.delete(key);
    }
    localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(shown)));
}

function esc(s) {
    return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
}

function overlayCheck(events) {
    if (!opts.overlay) return;
    const now = Date.now();
    for (const event of events) {
        if (event.allDay || shown.has(event.id)) continue;
        const since = now - event.start;
        // A check can land late (asleep, reload); anything older than the
        // grace window has been missed, not started, so leave it alone.
        if (since < 0 || since > 5 * 60000) continue;
        remember(event.id, event.end);
        const url = event.url || "";
        const html =
            `<style>
body { align-items: center; justify-content: center; text-align: center; gap: 20px; padding: 48px; }
h1 { font-size: 42px; }
#cd { font-size: 22px; }
.row { display: flex; gap: 12px; }
img { width: 200px; height: 200px; background: #fff; border-radius: 16px; padding: 12px; }
</style>
<h1>${esc(event.title || "Meeting")}</h1>
<p id="cd" class="muted">Starting now</p>
<div class="row">
${url ? `<button class="primary" onclick='send({ url: ${JSON.stringify(url)} })'>Join</button>` : ""}
<button onclick='send({ close: true })'>Close</button>
</div>
<script>
function send(msg) { webkit.messageHandlers.macotron.postMessage(msg); }
const start = ${event.start};
setInterval(() => {
  const m = Math.round((Date.now() - start) / 60000);
  document.getElementById("cd").textContent = m ? "Started " + m + "m ago" : "Starting now";
}, 1000);
</script>`;
        const id = macotron.panel.open({
            id: "meeting:" + event.id,
            title: event.title || "Meeting",
            html,
            glass: true,
            frameless: true,
            fullscreen: true,
            escapeCloses: false,
            qr: url || undefined,
        });
        macotron.panel.onMessage(id, (msg) => {
            if (msg && msg.url) macotron.url.open(msg.url);
            macotron.panel.close(id);
        });
    }
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
    overlayCheck(events);
}

paint();
macotron.every(30000, paint);

macotron.command("Next Meeting", "Open the next calendar event's meeting link", async () => {
    const next = nextTimed(await upcoming());
    if (!next) {
        macotron.notify.toast("No meetings", "Nothing in the next " + (opts.hours || 12) + " hours");
        return;
    }
    macotron.notify.toast(next.title || "Untitled", timeLabel(next.start));
    joinOrOpen(next);
});
