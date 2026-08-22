macotron.plugin({
    title: "Icon Rainbow Example",
    description: "Cycle the Macotron menu bar icon through rainbow colors.",
});

const colors = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE", "#007AFF", "#5856D6", "#AF52DE"];
let i = 0;

function tick() {
    macotron.menubar.setIconColor(colors[i % colors.length]);
    i++;
}

tick();
macotron.every(1000, tick);
