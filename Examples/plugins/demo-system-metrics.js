macotron.plugin({
  title: "System Metrics",
  description: "CPU and GPU usage in the menu bar.",
});

const GREEN = "#34C759";
const ORANGE = "#FF9500";
const RED = "#FF3B30";

function tint(n) {
    if (n >= 80) return RED;
    if (n >= 50) return ORANGE;
    return GREEN;
}

function snapshot() {
    const cpu = Math.round(macotron.system.cpu().usage);
    const gpu = macotron.system.gpu();
    const gpuN = Math.round(gpu && gpu.usage != null ? gpu.usage : 0);
    const mem = macotron.system.memory();
    const usedGB = (mem.used / (1024 * 1024 * 1024)).toFixed(1);
    const totalGB = (mem.total / (1024 * 1024 * 1024)).toFixed(0);
    const bat = macotron.system.battery();
    const disk = macotron.system.disk();
    const diskUsed = disk.total ? Math.round((disk.used / disk.total) * 100) : 0;
    return { cpu, gpuN, gpuName: gpu && gpu.name, usedGB, totalGB, bat, diskUsed };
}

function menu(s) {
    const rows = [
        { title: "CPU " + s.cpu + "%" },
        { title: "GPU " + s.gpuN + "%" + (s.gpuName ? " — " + s.gpuName : "") },
        { title: "Memory " + s.usedGB + "/" + s.totalGB + " GB" },
        { title: "Disk " + s.diskUsed + "% used" },
    ];
    if (s.bat && s.bat.level >= 0) {
        rows.push({
            title: "Battery " + Math.round(s.bat.level) + "%" + (s.bat.charging ? " charging" : ""),
        });
    }
    return rows;
}

function paint() {
    const s = snapshot();
    macotron.menubar.status("system-metrics", {
        title: "",
        sfSymbol: "cpu",
        color: tint(Math.max(s.cpu, s.gpuN)),
        menu: menu(s),
    });
    macotron.menubar.add("system-metrics-menu", {
        title: "CPU " + s.cpu + "%  ·  GPU " + s.gpuN + "%",
        icon: "cpu",
        section: "System",
    });
}

paint();
macotron.every(2000, paint);

macotron.command("System Metrics", "Show CPU and GPU usage", () => {
    const s = snapshot();
    macotron.notify.toast("CPU " + s.cpu + "%", "GPU " + s.gpuN + "%");
});
