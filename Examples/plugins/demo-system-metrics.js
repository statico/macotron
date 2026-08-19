// demo-system-metrics.js — disk free + GPU + network as a two-line status item
const GB = 1024 * 1024 * 1024;
const MB = 1024 * 1024;

function paint() {
    const { free } = macotron.system.disk();
    const gpu = macotron.system.gpu();
    const { bytesIn, bytesOut } = macotron.system.network();
    macotron.menubar.status("system-metrics", {
        title: `${(free / GB).toFixed(1)}G free`,
        subtitle: `${gpu ? gpu.name : "GPU"}  ↓${(bytesIn / MB).toFixed(0)} ↑${(bytesOut / MB).toFixed(0)}`,
        sfSymbol: "internaldrive",
    });
}

paint();
macotron.every(10_000, paint);

macotron.command("System Metrics", "Notify disk + GPU + network counters", () => {
    const { free } = macotron.system.disk();
    macotron.notify.show("System Metrics", `${(free / GB).toFixed(1)}G free`);
});
