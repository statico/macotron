macotron.plugin({
    title: "CPU, GPU and Memory Graph",
    description: "CPU core, GPU, and memory gauges in the menu bar.",
});

// Bars fill from the bottom; the donut runs clockwise from twelve o'clock.
const H = 18;
const BAR_W = 7;
const GAP = 4;
const R = 6; // donut radius
const RING = 4; // donut stroke width
const TRACK = "#98989D"; // graphite
const P_CORE = "#FF375F"; // pink: performance cores, wired memory
const E_CORE = "#0A84FF"; // blue: efficiency cores, app memory, GPU
const COMPRESSED = "#FFD60A"; // yellow: compressed memory
const GPU = E_CORE;

function bar(x, segments) {
    // segments: [{ frac, color }] stacked from the bottom, fracs sum to <= 1
    const clip = "clip" + x;
    let out =
        `<clipPath id="${clip}"><rect x="${x}" y="0" width="${BAR_W}" height="${H}" rx="${BAR_W / 2}"/></clipPath>` +
        `<rect x="${x}" y="0" width="${BAR_W}" height="${H}" rx="${BAR_W / 2}" fill="${TRACK}" fill-opacity="0.35"/>` +
        `<g clip-path="url(#${clip})">`;
    let y = H;
    for (const seg of segments) {
        const h = Math.max(0, Math.min(1, seg.frac)) * H;
        y -= h;
        out += `<rect x="${x}" y="${y}" width="${BAR_W}" height="${h}" fill="${seg.color}"/>`;
    }
    return out + "</g>";
}

function donut(cx, cy, segments) {
    const c = 2 * Math.PI * R;
    let out =
        `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${TRACK}" stroke-opacity="0.35" stroke-width="${RING}"/>`;
    let offset = 0;
    for (const seg of segments) {
        const len = Math.max(0, Math.min(1, seg.frac)) * c;
        if (len <= 0) continue;
        out +=
            `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${seg.color}" stroke-width="${RING}"` +
            ` stroke-dasharray="${len} ${c - len}" stroke-dashoffset="${-offset}"` +
            ` transform="rotate(-90 ${cx} ${cy})"/>`;
        offset += len;
    }
    return out;
}

function pct(n) {
    return Math.round(n) + "%";
}

function gb(bytes) {
    return (bytes / 1e9).toFixed(1) + " GB";
}

function paint() {
    const cpu = macotron.system.cpu();
    const gpu = macotron.system.gpu();
    const mem = macotron.system.memory();

    // Split the CPU bar by how much work each cluster actually contributed.
    const pWork = cpu.performance * cpu.performanceCores;
    const eWork = cpu.efficiency * cpu.efficiencyCores;
    const cores = cpu.performanceCores + cpu.efficiencyCores;
    const usage = cores > 0 ? (pWork + eWork) / cores : cpu.usage;

    const gpuUsage = gpu ? gpu.usage : 0;
    const app = Math.max(0, mem.used - mem.wired - mem.compressed);

    const donutX = BAR_W * 2 + GAP * 2 + RING / 2 + R;
    const width = donutX + R + RING / 2 + 2;
    const svg =
        `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${H}" viewBox="0 0 ${width} ${H}">` +
        bar(0, [
            { frac: (pWork / cores) / 100, color: P_CORE },
            { frac: (eWork / cores) / 100, color: E_CORE },
        ]) +
        bar(BAR_W + GAP, [{ frac: gpuUsage / 100, color: GPU }]) +
        donut(donutX, H / 2, [
            { frac: app / mem.total, color: E_CORE },
            { frac: mem.wired / mem.total, color: P_CORE },
            { frac: mem.compressed / mem.total, color: COMPRESSED },
        ]) +
        "</svg>";

    macotron.menubar.status("cpu-graph", {
        title: "",
        svg,
        menu: [
            { title: "CPU " + pct(usage) },
            { title: "  Performance " + pct(cpu.performance) + " (" + cpu.performanceCores + " cores)" },
            { title: "  Efficiency " + pct(cpu.efficiency) + " (" + cpu.efficiencyCores + " cores)" },
            { title: "GPU " + pct(gpuUsage) + (gpu ? " — " + gpu.name : "") },
            { title: "Memory " + gb(mem.used) + " of " + gb(mem.total) },
            { title: "  App " + gb(app) },
            { title: "  Wired " + gb(mem.wired) },
            { title: "  Compressed " + gb(mem.compressed) },
        ],
    });
}

paint();
macotron.every(2000, paint);
