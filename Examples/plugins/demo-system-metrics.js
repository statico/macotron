// demo-system-metrics.js — show free disk space in the menubar
const GB = 1024 * 1024 * 1024;

function diskTitle() {
    const { free } = macotron.system.disk();
    return `Disk: ${(free / GB).toFixed(1)} GB free`;
}

macotron.menubar.add("disk-free", {
    title: diskTitle(),
    icon: "internaldrive",
    section: "System"
});

macotron.every(10_000, () => {
    macotron.menubar.update("disk-free", { title: diskTitle() });
});
