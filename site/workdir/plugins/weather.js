// weather.js
// APIs: macotron.plugin, macotron.http.get, macotron.menubar.status, macotron.system.locale, macotron.every, macotron.notify, macotron.command

const opts = macotron.plugin({
    title: "Weather",
    description: "Current weather in the menu bar.",
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

const SYMBOLS = {
    "sun.max.fill": [113],
    "cloud.sun.fill": [116],
    "cloud.fill": [119, 122],
    "cloud.fog.fill": [143, 248, 260],
    "cloud.rain.fill": [176, 263, 266, 293, 296, 299, 302, 305, 308, 353, 356, 359],
    "cloud.bolt.rain.fill": [200, 386, 389, 392, 395],
    "cloud.snow.fill": [179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371],
    "cloud.sleet.fill": [182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377],
};

let lastWeather = null;
let lastObservation = null;

function weatherSymbol(code) {
    const number = Number(code);
    for (const symbol of Object.keys(SYMBOLS)) {
        if (SYMBOLS[symbol].includes(number)) return symbol;
    }
    return "cloud.fill";
}

function description(value) {
    return value && value.weatherDesc && value.weatherDesc[0]
        ? value.weatherDesc[0].value
        : "Unknown";
}

function validDate(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const parts = value.split("-").map(Number);
    const date = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
    return date.getUTCFullYear() === parts[0]
        && date.getUTCMonth() === parts[1] - 1
        && date.getUTCDate() === parts[2];
}

function hourMinutes(value) {
    const text = String(value).trim();
    if (!/^\d{1,4}$/.test(text)) return null;
    const time = text.padStart(4, "0");
    const hour = Number(time.slice(0, 2));
    const minute = Number(time.slice(2));
    return hour <= 23 && minute <= 59 ? hour * 60 + minute : null;
}

function dateMinutes(date, time) {
    const minutes = hourMinutes(time);
    if (!validDate(date) || minutes === null) return null;
    const parts = date.split("-").map(Number);
    return Date.UTC(parts[0], parts[1] - 1, parts[2]) / 60000 + minutes;
}

function observationKey(weather, value) {
    if (!weather.length || !validDate(weather[0].date)) return null;
    const text = String(value || "").trim();
    const local = text.match(/^(\d{4}-\d{2}-\d{2})\s+(\d{1,2}):(\d{2})\s+([AP]M)$/);
    const clock = text.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:([+-])(\d{2})(\d{2}))?$/);
    let date = weather[0].date;
    let hour;
    let minute;
    if (local) {
        date = local[1];
        const twelveHour = Number(local[2]);
        if (twelveHour < 1 || twelveHour > 12) return null;
        hour = twelveHour % 12;
        minute = Number(local[3]);
        if (local[4] === "PM") hour += 12;
    } else if (clock) {
        hour = Number(clock[1]);
        minute = Number(clock[2]);
        if (clock[3] !== undefined && Number(clock[3]) > 59) return null;
        if (clock[4] !== undefined) {
            const offsetHour = Number(clock[5]);
            const offsetMinute = Number(clock[6]);
            if (offsetHour > 14 || offsetMinute > 59
                || (offsetHour === 14 && offsetMinute !== 0)) return null;
        }
    } else {
        return null;
    }
    if (hour > 23 || minute > 59) return null;
    return dateMinutes(date, hour * 100 + minute);
}

function forecastHours(weather, observation) {
    const after = observationKey(weather, observation);
    if (after === null) return [];
    const entries = [];
    for (const day of weather) {
        for (const hour of day.hourly || []) {
            const time = String(hour.time || "0").padStart(4, "0");
            const key = dateMinutes(day.date, time);
            if (key >= after) entries.push({ date: day.date, time: time, value: hour });
        }
    }
    entries.sort((a, b) => dateMinutes(a.date, a.time) - dateMinutes(b.date, b.time));
    return entries.slice(0, 4);
}

function validDescription(value) {
    return value && Array.isArray(value.weatherDesc)
        && value.weatherDesc[0] && typeof value.weatherDesc[0].value === "string"
        && value.weatherDesc[0].value.trim() !== "";
}

function numeric(value) {
    if (typeof value === "number") return isFinite(value);
    return typeof value === "string"
        && /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value.trim())
        && isFinite(Number(value));
}

function validWeatherStructure(data) {
    if (!data || !Array.isArray(data.current_condition) || !data.current_condition[0]
        || !Array.isArray(data.weather) || data.weather.length < 3) return false;
    const current = data.current_condition[0];
    const currentFields = [
        "temp_C", "temp_F", "FeelsLikeC", "FeelsLikeF", "humidity",
        "windspeedKmph", "windspeedMiles", "uvIndex", "visibility",
        "visibilityMiles", "weatherCode",
    ];
    if (currentFields.some((field) => !numeric(current[field]))
        || !validDescription(current)) return false;
    for (let index = 0; index < data.weather.length; index++) {
        const day = data.weather[index];
        if (!day || !validDate(day.date) || !Array.isArray(day.hourly)) return false;
        if (index < 3) {
            const fields = ["mintempC", "maxtempC", "mintempF", "maxtempF"];
            if (fields.some((field) => !numeric(day[field])) || !day.hourly.length) return false;
        }
        for (const hour of day.hourly) {
            if (!hour || hourMinutes(hour.time) === null || !numeric(hour.tempC)
                || !numeric(hour.tempF) || !numeric(hour.weatherCode)
                || !validDescription(hour)) return false;
        }
    }
    return true;
}

function validWeather(data, observation) {
    if (!validWeatherStructure(data) || observationKey(data.weather, observation) === null) {
        return false;
    }
    const hours = forecastHours(data.weather, observation);
    if (hours.length !== 4) return false;
    for (let index = 1; index < hours.length; index++) {
        if (dateMinutes(hours[index].date, hours[index].time)
            - dateMinutes(hours[index - 1].date, hours[index - 1].time) !== 180) return false;
    }
    return true;
}

function dayLabel(date) {
    const parts = date.split("-").map(Number);
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][
        new Date(Date.UTC(parts[0], parts[1] - 1, parts[2])).getUTCDay()
    ];
}

function timeLabel(time) {
    const hour = Number(time.slice(0, 2));
    return (hour % 12 || 12) + (hour < 12 ? " AM" : " PM");
}

function dailyCondition(day) {
    return day.hourly.reduce((closest, hour) => {
        const time = String(hour.time || "0").padStart(4, "0");
        const minutes = Number(time.slice(0, 2)) * 60 + Number(time.slice(2));
        return !closest || Math.abs(minutes - 720) < closest.distance
            ? { value: hour, distance: Math.abs(minutes - 720) }
            : closest;
    }, null).value;
}

function locationName(data) {
    const area = data.nearest_area && data.nearest_area[0];
    if (!area) return opts.location || "Current location";
    const names = [area.areaName, area.region, area.country]
        .map((field) => field && field[0] && field[0].value)
        .filter(Boolean);
    return names.join(", ");
}

function weatherMenu(data, units, error, observation) {
    const current = data.current_condition[0];
    const us = units === "us";
    const feelsLike = us ? current.FeelsLikeF : current.FeelsLikeC;
    const wind = us ? current.windspeedMiles + " mph" : current.windspeedKmph + " km/h";
    const visibility = us ? current.visibilityMiles + " miles" : current.visibility + " km";
    const rows = [
        {
            title: locationName(data) + " · " + description(current),
            icon: weatherSymbol(current.weatherCode),
        },
        "-",
        { title: "Feels like " + feelsLike + "°", icon: "thermometer.medium" },
        { title: "Humidity " + current.humidity + "%", icon: "humidity.fill" },
        { title: "Wind " + wind, icon: "wind" },
        { title: "UV index " + current.uvIndex, icon: "sun.max" },
        { title: "Visibility " + visibility, icon: "eye" },
        "-",
        {
            title: "Next 12 Hours",
            menu: forecastHours(
                data.weather,
                observation == null ? current.localObsDateTime : observation
            ).map((entry) => {
                const hour = entry.value;
                return {
                    title: timeLabel(entry.time) + " · "
                        + (us ? hour.tempF : hour.tempC) + "° · " + description(hour),
                    icon: weatherSymbol(hour.weatherCode),
                };
            }),
        },
        "-",
    ];
    for (const day of data.weather.slice(0, 3)) {
        const condition = dailyCondition(day);
        rows.push({
            title: dayLabel(day.date) + " · "
                + (us ? day.mintempF : day.mintempC) + "°–"
                + (us ? day.maxtempF : day.maxtempC) + "° · " + description(condition),
            icon: weatherSymbol(condition.weatherCode),
        });
    }
    if (error) rows.push({ title: "Update failed: " + error });
    rows.push("-", { title: "Refresh", onClick: () => refreshWeather() });
    return rows;
}

function renderWeather(data, observation, units, error) {
    const current = data.current_condition[0];
    macotron.menubar.status("weather", {
        title: (units === "us" ? current.temp_F : current.temp_C) + "°",
        sfSymbol: weatherSymbol(current.weatherCode),
        menu: weatherMenu(data, units, error, observation),
    });
}

async function resolveObservation(data, path) {
    const local = data.current_condition[0].localObsDateTime;
    if (local !== undefined && local !== null) return local;
    const res = await macotron.http.get(`https://wttr.in/${path}?format=%T`, {
        headers: { "User-Agent": "curl" },
    });
    if (res.status < 200 || res.status >= 300 || !res.body) {
        throw new Error(`HTTP ${res.status}`);
    }
    return res.body.trim();
}

async function refreshWeather() {
    const loc = (opts.location || "").trim();
    const units = macotron.system.locale().measurement === "us" ? "us" : "metric";
    const path = loc ? encodeURIComponent(loc) : "";
    const url = `https://wttr.in/${path}?format=j1`;

    try {
        const res = await macotron.http.get(url, {
            headers: { "User-Agent": "curl" },
        });
        if (res.status < 200 || res.status >= 300 || !res.body) {
            throw new Error(`HTTP ${res.status}`);
        }
        const data = JSON.parse(res.body);
        if (!validWeatherStructure(data)) {
            throw new Error("Invalid weather response");
        }
        const observation = await resolveObservation(data, path);
        if (!validWeather(data, observation)) throw new Error("Invalid local observation time");
        lastWeather = data;
        lastObservation = observation;
        renderWeather(data, observation, units, null);
        return true;
    } catch (err) {
        if (lastWeather && validWeather(lastWeather, lastObservation)) {
            renderWeather(lastWeather, lastObservation, units, err.message || String(err));
        } else {
            lastWeather = null;
            lastObservation = null;
            macotron.menubar.status("weather", {
                title: "—",
                color: "red",
                menu: [
                    { title: "Weather failed: " + (err.message || String(err)) },
                    "-",
                    { title: "Refresh", onClick: () => refreshWeather() },
                ],
            });
        }
        macotron.log("weather fetch failed", err);
        return false;
    }
}

macotron.every(opts.refreshMs || 600000, refreshWeather);
refreshWeather();

macotron.command("Refresh Weather", "Refresh the menu bar weather", () => {
    refreshWeather().then((success) => macotron.notify.toast(
        "Weather",
        success ? "Updated" : "Update failed",
        { color: success ? "success" : "error" }
    ));
});
