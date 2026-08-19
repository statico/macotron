// demo-weather.js
// APIs: macotron.module, macotron.http.get, macotron.menubar.status, macotron.every, macotron.notify, macotron.command

const opts = macotron.module({
    title: "Weather",
    description: "Menubar weather via wttr.in",
    options: {
        location: {
            type: "string",
            label: "Location (city or airport)",
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
        sfSymbol: "cloud.sun",
        color: color,
        menu: [
            { title: "Refresh", onClick: () => refreshWeather() },
        ],
    });
}

async function refreshWeather() {
    const loc = (opts.location || "").trim();
    const path = loc ? encodeURIComponent(loc) : "";
    const url = `https://wttr.in/${path}?format=%c+%t`;

    try {
        const res = await macotron.http.get(url, {
            headers: { "User-Agent": "curl" },
        });
        if (res.status < 200 || res.status >= 300 || !res.body) {
            throw new Error(`HTTP ${res.status}`);
        }
        const title = res.body.trim().replace(/\n/g, " ");
        render(title || "Weather", null);
    } catch (err) {
        render("Weather —", "red");
        macotron.log("weather fetch failed", err);
    }
}

macotron.every(opts.refreshMs || 600000, refreshWeather);
refreshWeather();

macotron.command("Refresh Weather", "Fetch wttr.in into the menubar", () => {
    refreshWeather().then(() => macotron.notify.show("Weather", "Updated"));
});
