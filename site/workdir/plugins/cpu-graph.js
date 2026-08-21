macotron.plugin({
    title: "CPU Graph",
    description: "Show CPU usage in the menu bar.",
});

const values = [];
const MAX = 30;

function paint() {
    const cpu = macotron.system.cpu().usage;
    values.push(cpu);
    if (values.length > MAX) values.shift();
    macotron.menubar.status("cpu-graph", {
        title: Math.round(cpu) + "%",
        sparkline: { values, width: 36, height: 18, color: "#34C759" },
        menu: [{ title: "CPU " + Math.round(cpu) + "%" }],
    });
}

paint();
macotron.every(2000, paint);
