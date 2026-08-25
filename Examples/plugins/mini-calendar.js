const opts = macotron.plugin({
    title: "Mini Calendar",
    description: "Show today's weekday and date in the menu bar, with the month in its menu.",
    options: {
        clocks: {
            type: "text",
            label: "World clocks",
            help: "One IANA time zone per line, such as Europe/London. Each may be renamed with 'Zone = Label'. Shown under the month.",
            default: "",
        },
    },
});

const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"];

// The bottom half is a filled block with the date knocked out of it, so the
// number gets the whole width instead of leaving room for a border.
//
// macOS rasterizes text-anchor="middle" about a point right of true centre
// (measured across every day of the month), so the anchor sits left of the
// middle to land the digits on it.
const MID = 10.1;

// Any solid color does: the icon ships as a template, so only its alpha
// survives and the menu bar picks the ink.
const INK = "#000000";

function icon(date) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="18" viewBox="0 0 22 18">
<mask id="k">
<rect x="0" y="0" width="22" height="18" fill="white"/>
<rect x="1.8" y="1.8" width="18.4" height="6.9" rx="1.9" fill="black"/>
<text x="${MID}" y="16.3" font-family="Helvetica-Bold" font-size="9.2" text-anchor="middle" fill="black">${date.getDate()}</text>
</mask>
<rect x="0.5" y="0.5" width="21" height="17" rx="3.1" fill="${INK}" mask="url(#k)"/>
<text x="${MID + 0.4}" y="7.35" font-family="Helvetica-Bold" font-size="5.7" text-anchor="middle" fill="${INK}">${DOW[date.getDay()]}</text>
</svg>`;
}

// Months away from this one. The buttons move it; Today puts it back.
let offset = 0;
const ROW = 18;
const CLOCK_ROW = 17;

function shownMonth(now) {
    return new Date(now.getFullYear(), now.getMonth() + offset, 1);
}

// The month as a web page: the menu itself is the calendar, so there is no
// panel to open. `cal` would need a shell round trip and the menu is built
// synchronously, so lay the weeks out here instead.
function weeks(now, shown) {
    const lead = shown.getDay();
    const days = new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate();
    const before = new Date(shown.getFullYear(), shown.getMonth(), 0).getDate();
    const trail = (7 - ((lead + days) % 7)) % 7;
    // Neighbouring days are dimmed rather than blank, so every row is a full
    // week instead of a ragged edge.
    let cells = "";
    for (let i = lead; i > 0; i--) cells += `<div class="off">${before - i + 1}</div>`;
    for (let d = 1; d <= days; d++) {
        const today = d === now.getDate()
            && shown.getMonth() === now.getMonth()
            && shown.getFullYear() === now.getFullYear();
        cells += `<div${today ? ' class="today"' : ""}>${d}</div>`;
    }
    for (let d = 1; d <= trail; d++) cells += `<div class="off">${d}</div>`;
    return { cells, rows: (lead + days + trail) / 7 };
}

function grid(cells) {
    return `<style>
#m { display:grid; grid-template-columns:repeat(7, 1fr); text-align:center;
     font-size:11px; line-height:${ROW}px; font-variant-numeric:tabular-nums; }
#m .dow { opacity:0.5; font-size:9px; text-transform:uppercase; }
#m .off { opacity:0.35; }
#m .today { background:Highlight; color:HighlightText; border-radius:9px; }
</style>
<div id="m">${DOW.map((d) => `<div class="dow">${d[0]}${d[1].toLowerCase()}</div>`).join("")}${cells}</div>`;
}

// Its own menu item, so it can sit under the month buttons rather than
// between them and the grid.
function clockList(clockRows) {
    return `<style>
#c { display:grid; grid-template-columns:1fr auto; gap:0 12px;
     font-size:11px; line-height:${CLOCK_ROW}px; font-variant-numeric:tabular-nums; }
#c .t { text-align:right; opacity:0.75; }
</style>
<div id="c">${clockRows.map((c) => `<div>${esc(c.label)}</div><div class="t">${esc(c.time)}</div>`).join("")}</div>`;
}

function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;");
}

// QuickJS has no Intl, so the host does the zone conversion. An unknown zone
// comes back empty and is dropped rather than showing a blank row.
// "Europe/London" titles itself London; "Europe/London = Home" says Home.
function clocks() {
    return String(opts.clocks || "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean)
        .map((line) => {
            const [zone, label] = line.split("=").map((part) => part.trim());
            return {
                label: label || zone.split("/").pop().replace(/_/g, " "),
                time: macotron.system.timeIn(zone),
            };
        })
        .filter((c) => c.time);
}

function move(by) {
    offset += by;
    render();
}

function render() {
    const now = new Date();
    const shown = shownMonth(now);
    const month = weeks(now, shown);
    const clockRows = clocks();
    macotron.menubar.status("mini-calendar", {
        title: "",
        svg: icon(now),
        // The bar is tinted from the wallpaper, so it disagrees with the
        // appearance setting often enough that baked-in ink is a coin flip.
        // As a mask, the bar tints it to suit whatever it is sitting on.
        template: true,
        // No onClick, so a left-click drops the menu -- and the month with it.
        menu: [
            { title: `${MONTHS[shown.getMonth()]} ${shown.getFullYear()}` },
            {
                html: grid(month.cells),
                width: 220,
                height: (month.rows + 1) * ROW + 6,
            },
            // A button row keeps the menu open, so the month can be paged
            // without the menu closing on every step.
            { buttons: [
                { title: "‹", onClick: () => move(-1) },
                { title: "Today", onClick: () => move(-offset) },
                { title: "›", onClick: () => move(1) },
            ] },
            ...(clockRows.length ? ["-", {
                html: clockList(clockRows),
                width: 220,
                height: clockRows.length * CLOCK_ROW + 8,
            }] : []),
            "-",
            { title: "Open Calendar…", onClick: () => macotron.app.launch("com.apple.iCal") },
        ],
    });
}

render();
macotron.every(60000, render);

macotron.command("Open Calendar", "Open the Calendar app", () =>
    macotron.app.launch("com.apple.iCal"));
