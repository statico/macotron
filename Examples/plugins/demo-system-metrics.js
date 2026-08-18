// demo-system-metrics.js — disk free + GPU + network in the menubar
const GB = 1024 * 1024 * 1024;
const MB = 1024 * 1024;

function summary() {
    const { free } = macotron.system.disk();
    const gpu = macotron.system.gpu();
    const { bytesIn, bytesOut } = macotron.system.network();
    const gpuLabel = gpu ? gpu.name : "GPU?";
    return `Disk ${(free / GB).toFixed(1)}G · ${gpuLabel} · ↓${(bytesIn / MB).toFixed(0)} ↑${(bytesOut / MB).toFixed(0)} MB`;
}

macotron.menubar.add("system-metrics", {
    title: summary(),
    icon: "internaldrive",
    section: "System"
});

macotron.every(10_000, () => {
    macotron.menubar.update("system-metrics", { title: summary() });
});

macotron.command("System Metrics", "Notify disk + GPU + network counters", () => {
    macotron.notify.show("System Metrics", summary());
});
