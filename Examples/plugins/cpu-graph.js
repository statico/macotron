macotron.plugin({
    title: "CPU, GPU and Memory Graph",
    description: "CPU core, GPU, and memory gauges in the menu bar, with the top processes for each.",
});

const TOP_N = 8;
const PS = ["-Aceo", "pid=,pcpu=,rss=,comm="];
// Apple silicon's GPU driver keeps a running GPU-time total per client; Intel Macs have none, so the GPU list stays empty there.
const IOREG = ["-r", "-c", "AGXDeviceUserClient", "-l"];

let top = { cpu: [], gpu: [], mem: [] };
let lastGPU = null; // { at, ns: Map<pid, ns> }

async function sampleGPU() {
    const res = await macotron.shell.run("/usr/sbin/ioreg", IOREG);
    if (res.exitCode !== 0) return new Map();
    const ns = new Map();
    // One "+-o" block per client: its creator pid and the GPU time of each of its queues.
    for (const block of res.stdout.split("+-o ")) {
        const pid = Number(/"IOUserClientCreator" = "pid (\d+)/.exec(block)?.[1]);
        if (!pid) continue;
        const t = [...block.matchAll(/"accumulatedGPUTime"=(\d+)/g)].reduce((sum, m) => sum + Number(m[1]), 0);
        ns.set(pid, (ns.get(pid) || 0) + t);
    }
    const now = Date.now();
    const pct = new Map();
    if (lastGPU) {
        const elapsed = (now - lastGPU.at) * 1e6;
        for (const [pid, t] of ns) {
            const d = t - (lastGPU.ns.get(pid) ?? t);
            if (d > 0) pct.set(pid, (d / elapsed) * 100);
        }
    }
    lastGPU = { at: now, ns };
    return pct;
}

async function sampleTop() {
    const [ps, gpu] = await Promise.all([macotron.shell.run("/bin/ps", PS), sampleGPU().catch(() => new Map())]);
    const procs = [];
    for (const line of ps.stdout.split("\n")) {
        const m = /^\s*(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/.exec(line);
        if (m) procs.push({ pid: +m[1], cpu: +m[2], mem: +m[3] * 1024, name: m[4], gpu: gpu.get(+m[1]) || 0 });
    }
    const best = (key) => procs.filter((p) => p[key] > 0).sort((a, b) => b[key] - a[key]).slice(0, TOP_N);
    top = { cpu: best("cpu"), gpu: best("gpu"), mem: best("mem") };
}

function topMenu(title, list, fmt) {
    const rows = list.map((p) => ({ title: fmt(p) + "  " + p.name }));
    return { title, menu: rows.length ? rows : [{ title: "Nothing to show", dimmed: true }] };
}

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
    let out = `<clipPath id="${clip}"><rect x="${x}" y="0" width="${BAR_W}" height="${H}" rx="${BAR_W / 2}"/></clipPath><rect x="${x}" y="0" width="${BAR_W}" height="${H}" rx="${BAR_W / 2}" fill="${TRACK}" fill-opacity="0.35"/><g clip-path="url(#${clip})">`;
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
    let out = `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${TRACK}" stroke-opacity="0.35" stroke-width="${RING}"/>`;
    let offset = 0;
    for (const seg of segments) {
        const len = Math.max(0, Math.min(1, seg.frac)) * c;
        if (len <= 0) continue;
        out += `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${seg.color}" stroke-width="${RING}" stroke-dasharray="${len} ${c - len}" stroke-dashoffset="${-offset}" transform="rotate(-90 ${cx} ${cy})"/>`;
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

let busy = false;
async function paint() {
    if (busy) return;
    busy = true;
    try {
        await sampleTop();
    } catch (e) {
        console.error("cpu-graph: process sample failed", e);
    } finally {
        busy = false;
    }

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
            "-",
            topMenu("Top CPU", top.cpu, (p) => pct(p.cpu)),
            topMenu("Top GPU", top.gpu, (p) => pct(p.gpu)),
            topMenu("Top Memory", top.mem, (p) => gb(p.mem)),
            "-",
            { title: "Open Activity Monitor", onClick: () => macotron.app.launch("com.apple.ActivityMonitor") },
        ],
    });
}

paint();
macotron.every(2000, paint);
