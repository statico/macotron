// demo-weather.js
// APIs: macotron.plugin, macotron.http.get, macotron.menubar.status, macotron.system.locale, macotron.every, macotron.notify, macotron.command

const opts = macotron.plugin({
    title: "Weather",
    description: "Menubar weather via wttr.in",
    options: {
        location: {
            type: "string",
            label: "Location (city or airport, blank = IP)",
            default: "",
        },
        refreshMs: {
            type: "number",
            label: "Refresh interval (ms)",
            default: 600000,
        },
    },
});

function render(title, color) {
    macotron.menubar.status("weather", {
        title: title,
        color: color,
        menu: [
            { title: "Refresh", onClick: () => refreshWeather() },
        ],
    });
}

async function refreshWeather() {
    const loc = (opts.location || "").trim();
    const units = macotron.system.locale().measurement === "us" ? "u" : "m";
    const path = loc ? encodeURIComponent(loc) : "";
    const url = `https://wttr.in/${path}?${units}&format=%c+%t`;

    try {
        const res = await macotron.http.get(url, {
            headers: { "User-Agent": "curl" },
        });
        if (res.status < 200 || res.status >= 300 || !res.body) {
            throw new Error(`HTTP ${res.status}`);
        }
        const title = res.body.trim().replace(/\s+/g, " ").replace(/\+(\d)/g, "$1");
        render(title || "Weather", null);
    } catch (err) {
        render("—", "red");
        macotron.log("weather fetch failed", err);
    }
}

macotron.every(opts.refreshMs || 600000, refreshWeather);
refreshWeather();

macotron.command("Refresh Weather", "Fetch wttr.in into the menubar", () => {
    refreshWeather().then(() => macotron.notify.toast("Weather", "Updated", { color: "success" }));
});
