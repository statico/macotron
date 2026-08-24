macotron.plugin({
    title: "Mini Calendar",
    description: "Show today's weekday and date in the menu bar, with the month in its menu.",
});

const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

// The bottom half is a filled block with the date knocked out of it, so the
// number gets the whole width instead of leaving room for a border.
//
// macOS rasterizes text-anchor="middle" about a point right of true centre
// (measured across every day of the month), so the anchor sits left of the
// middle to land the digits on it.
const MID = 10.1;

function icon(date, ink) {
    return `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="18" viewBox="0 0 22 18">
<mask id="k">
<rect x="0" y="0" width="22" height="18" fill="white"/>
<rect x="1.8" y="1.8" width="18.4" height="6.9" rx="1.9" fill="black"/>
<text x="${MID}" y="16.3" font-family="Helvetica-Bold" font-size="9.2" text-anchor="middle" fill="black">${date.getDate()}</text>
</mask>
<rect x="0.5" y="0.5" width="21" height="17" rx="3.1" fill="${ink}" mask="url(#k)"/>
<text x="${MID + 0.4}" y="7.35" font-family="Helvetica-Bold" font-size="5.7" text-anchor="middle" fill="${ink}">${DOW[date.getDay()]}</text>
</svg>`;
}

// The month as a web page: the menu itself is the calendar, so there is no
// panel to open. `cal` would need a shell round trip and the menu is built
// synchronously, so lay the weeks out here instead.
function grid(now) {
    const first = new Date(now.getFullYear(), now.getMonth(), 1).getDay();
    const days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    let cells = "";
    for (let i = 0; i < first; i++) cells += "<div></div>";
    for (let d = 1; d <= days; d++) {
        cells += `<div${d === now.getDate() ? ' class="today"' : ""}>${d}</div>`;
    }
    return `<style>
#m { display:grid; grid-template-columns:repeat(7, 1fr); text-align:center;
     font-size:11px; line-height:18px; font-variant-numeric:tabular-nums; }
#m .dow { opacity:0.5; font-size:9px; text-transform:uppercase; }
#m .today { background:Highlight; color:HighlightText; border-radius:9px; }
</style>
<div id="m">${DOW.map((d) => `<div class="dow">${d[0]}${d[1].toLowerCase()}</div>`).join("")}${cells}</div>`;
}

function render() {
    const now = new Date();
    macotron.menubar.status("mini-calendar", {
        title: "",
        svg: icon(now, macotron.system.darkMode() ? "#ffffff" : "#000000"),
        // No onClick, so a left-click drops the menu -- and the month with it.
        menu: [
            { title: now.toDateString() },
            { html: grid(now), width: 220, height: 130 },
            "-",
            { title: "Open Calendar…", onClick: () => macotron.app.launch("com.apple.iCal") },
        ],
    });
}

render();
macotron.every(60000, render);

macotron.command("Open Calendar", "Open the Calendar app", () =>
    macotron.app.launch("com.apple.iCal"));
