// Demo for the homepage recordings: two-line menu bar items with stoplight
// colors, the shape of a work plugin that asks "is production up to date?"
// The commit counts are canned so every clip shows the same menu bar. A real
// one would read them with macotron.http.
macotron.plugin({
    title: "Deploy Status",
    description: "Two-line menu bar items: how far each environment is behind main.",
});

const ENVS = [
    { id: "prod", label: "prod", behind: 1 },
    { id: "staging", label: "staging", behind: 0 },
];

function color(n) {
    if (n === 0) return "green";
    return n < 5 ? "yellow" : "red";
}

for (const env of ENVS) {
    const n = env.behind;
    macotron.menubar.status(env.id, {
        title: env.label,
        subtitle: n === 0 ? "✓ current" : "↓ " + n,
        subtitleColor: color(n),
        bold: true,
        secondary: true,
        minWidth: 44,
    });
}
