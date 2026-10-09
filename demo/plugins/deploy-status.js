// Demo for the homepage recordings: two-line menu bar items with stoplight
// colors, the shape of a work plugin that asks "is production up to date?"
// The commit counts are canned and step on a timer so the recording shows
// green, yellow and red. A real one would read them with macotron.http.
macotron.plugin({
    title: "Deploy Status",
    description: "Two-line menu bar items: how far each environment is behind main.",
});

const ENVS = [
    { id: "prod", label: "prod", behind: [0, 0, 2, 3, 9, 14, 0] },
    { id: "staging", label: "staging", behind: [0, 1, 0, 0, 1, 0, 0] },
];

function color(n) {
    if (n === 0) return "green";
    return n < 5 ? "yellow" : "red";
}

let step = 0;
function render() {
    for (const env of ENVS) {
        const n = env.behind[step % env.behind.length];
        macotron.menubar.status(env.id, {
            title: env.label,
            subtitle: n === 0 ? "✓ current" : "↓ " + n,
            subtitleColor: color(n),
            bold: true,
            secondary: true,
            minWidth: 44,
        });
    }
    step++;
}

render();
macotron.every(2500, render);
