// APIs: launcher.query, clipboard, notify

macotron.plugin({
    title: "Calculator",
    description: "Do math and convert units straight from the launcher.",
    help: "Open the launcher and type a sum (`12 * (3 + 4)`, `20% of 85`, `sqrt(2)`) or a "
        + "conversion (`12 km in miles`, `100f to c`, `2 GB in MB`). The answer appears as the "
        + "first result. Return copies it to the clipboard.",
});

const FUNCS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round,
    floor: Math.floor, ceil: Math.ceil, exp: Math.exp, sign: Math.sign,
    ln: Math.log, log: Math.log10, log2: Math.log2, log10: Math.log10,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin,
    acos: Math.acos, atan: Math.atan, hypot: Math.hypot, pow: Math.pow,
    min: Math.min, max: Math.max,
    pi: Math.PI, e: Math.E, tau: Math.PI * 2,
};
const NAMES = Object.keys(FUNCS);

// Everything is stored as a multiple of the unit's base (metres, grams, …), so a
// conversion is one multiply and one divide. Temperature is the exception and
// gets its own path below.
const UNITS = {
    length: {
        base: "m",
        of: { nm: 1e-9, um: 1e-6, mm: 0.001, cm: 0.01, m: 1, km: 1000, inch: 0.0254,
              in: 0.0254, ft: 0.3048, foot: 0.3048, feet: 0.3048, yd: 0.9144, yard: 0.9144,
              mi: 1609.344, mile: 1609.344, nmi: 1852, ly: 9.4607304725808e15 },
    },
    mass: {
        base: "kg",
        of: { mg: 1e-6, g: 0.001, kg: 1, t: 1000, tonne: 1000, oz: 0.028349523125,
              ounce: 0.028349523125, lb: 0.45359237, pound: 0.45359237, st: 6.35029318,
              stone: 6.35029318 },
    },
    data: {
        base: "MB",
        of: { b: 1e-6, byte: 1e-6, kb: 0.001, mb: 1, gb: 1000, tb: 1e6, pb: 1e9,
              kib: 0.001024, mib: 1.048576, gib: 1073.741824, tib: 1099511.627776,
              bit: 1.25e-7, kbit: 1.25e-4, mbit: 0.125, gbit: 125 },
    },
    time: {
        base: "s",
        of: { ms: 0.001, s: 1, sec: 1, second: 1, min: 60, minute: 60, h: 3600, hr: 3600,
              hour: 3600, d: 86400, day: 86400, wk: 604800, week: 604800,
              mo: 2629746, month: 2629746, y: 31556952, yr: 31556952, year: 31556952 },
    },
    speed: {
        base: "m/s",
        of: { "m/s": 1, mps: 1, "km/h": 1 / 3.6, kmh: 1 / 3.6, kph: 1 / 3.6,
              mph: 0.44704, "mi/h": 0.44704, kn: 0.514444, knot: 0.514444, c: 299792458 },
    },
    volume: {
        base: "l",
        of: { ml: 0.001, cl: 0.01, dl: 0.1, l: 1, liter: 1, litre: 1, m3: 1000,
              tsp: 0.00492892159375, tbsp: 0.01478676478125, floz: 0.0295735295625,
              cup: 0.2365882365, pt: 0.473176473, qt: 0.946352946, gal: 3.785411784,
              gallon: 3.785411784 },
    },
    area: {
        base: "m2", 
        of: { mm2: 1e-6, cm2: 1e-4, m2: 1, km2: 1e6, ha: 1e4, acre: 4046.8564224,
              ft2: 0.09290304, yd2: 0.83612736, mi2: 2589988.110336 },
    },
    angle: {
        base: "deg",
        of: { deg: 1, rad: 180 / Math.PI, grad: 0.9, turn: 360 },
    },
};

// Kelvin is the pivot: everything in and out goes through it.
const TEMPS = {
    c: { to: (v) => v + 273.15, from: (k) => k - 273.15 },
    celsius: { to: (v) => v + 273.15, from: (k) => k - 273.15 },
    f: { to: (v) => (v + 459.67) * 5 / 9, from: (k) => k * 9 / 5 - 459.67 },
    fahrenheit: { to: (v) => (v + 459.67) * 5 / 9, from: (k) => k * 9 / 5 - 459.67 },
    k: { to: (v) => v, from: (k) => k },
    kelvin: { to: (v) => v, from: (k) => k },
};

function findUnit(raw) {
    let u = String(raw || "").toLowerCase().replace(/[°"']/g, "");
    if (TEMPS[u]) return { temp: u, label: raw };
    for (const dim of Object.keys(UNITS)) {
        const table = UNITS[dim].of;
        if (table[u] != null) return { dim, unit: u, label: raw };
        // "miles", "hours", "gallons" — drop a plural s and try once more.
        const singular = u.replace(/s$/, "");
        if (table[singular] != null) return { dim, unit: singular, label: raw };
    }
    return null;
}

function group(text) {
    const parts = text.split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".");
}

function fmt(n) {
    if (typeof n !== "number" || !isFinite(n)) return null;
    const abs = Math.abs(n);
    if (abs !== 0 && (abs < 1e-6 || abs >= 1e15)) {
        return n.toExponential(6).replace(/\.?0+e/, "e");
    }
    // Round off the float dust (0.1 + 0.2) without truncating real precision.
    const text = String(Math.round(n * 1e9) / 1e9);
    const sign = text.startsWith("-") ? "-" : "";
    return sign + group(text.replace(/^-/, ""));
}

function convert(query) {
    const m = query.match(
        /^\s*(-?[\d.,]+(?:e-?\d+)?)\s*([a-zA-Z°"'/²³]+(?:\s*\/\s*[a-zA-Z]+)?)\s+(?:in|to|as|into)\s+([a-zA-Z°"'/²³]+(?:\s*\/\s*[a-zA-Z]+)?)\s*$/i
    );
    if (!m) return null;
    const value = Number(m[1].replace(/,/g, ""));
    if (!isFinite(value)) return null;
    const from = findUnit(m[2].replace(/\s+/g, ""));
    const to = findUnit(m[3].replace(/\s+/g, ""));
    if (!from || !to) return null;

    if (from.temp || to.temp) {
        if (!from.temp || !to.temp) return null;
        return { value: TEMPS[to.temp].from(TEMPS[from.temp].to(value)), unit: to.label };
    }
    if (from.dim !== to.dim) return null;
    const table = UNITS[from.dim].of;
    return { value: (value * table[from.unit]) / table[to.unit], unit: to.label };
}

function evaluate(query) {
    let src = query.trim();
    if (!/\d/.test(src)) return null;
    src = src
        .replace(/[×✕]/g, "*")
        .replace(/[÷]/g, "/")
        .replace(/,(?=\d{3}(\D|$))/g, "")
        .replace(/(\d(?:[\d.]*)?)\s*%\s+of\s+/gi, "($1/100)*")
        .replace(/([\d.)])\s*\+\s*([\d.]+)\s*%/g, "$1*(1+$2/100)")
        .replace(/([\d.)])\s*-\s*([\d.]+)\s*%/g, "$1*(1-$2/100)")
        .replace(/\^/g, "**");

    // Only an expression earns a result; a bare number is not worth a row.
    if (!/[+\-*/%^(]/.test(src) && !/[a-z]/i.test(src)) return null;
    // Any word that is not a function or constant we know means this is not maths.
    // The lookbehind keeps the `e` of `1e3` out of the identifier check.
    if (src.replace(/(?<![\d.])[a-z_][a-z0-9_]*/gi, (word) =>
        FUNCS[word.toLowerCase()] != null ? "" : "?"
    ).includes("?")) return null;
    if (!/^[0-9a-z_+\-*/%().\s]*$/i.test(src)) return null;

    try {
        const value = Function(...NAMES, '"use strict"; return (' + src + ");")(
            ...NAMES.map((n) => FUNCS[n])
        );
        return typeof value === "number" && isFinite(value) ? { value } : null;
    } catch {
        return null;
    }
}

function answer(query) {
    const conversion = convert(query);
    if (conversion) return { ...conversion, kind: "Conversion" };
    const math = evaluate(query);
    return math ? { ...math, kind: "Calculator" } : null;
}

macotron.launcher.query("calculator", (query) => {
    const hit = answer(String(query || ""));
    if (!hit) return [];
    const text = fmt(hit.value);
    if (text == null) return [];
    const full = hit.unit ? text + " " + hit.unit : text;
    return [{
        id: "result",
        title: full,
        subtitle: query.trim() + "  ·  Return to copy",
        sfSymbol: hit.kind === "Conversion" ? "arrow.left.arrow.right" : "equal.square",
        kind: hit.kind,
        onClick: () => {
            macotron.clipboard.set(full);
            macotron.notify.toast("Copied", full, { color: "success" });
        },
    }];
});
