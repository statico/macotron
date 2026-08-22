// APIs: url.open, command
macotron.plugin({
  title: "Open GitHub in Safari",
  description: "Open all GitHub links in Safari.",
});

macotron.command("Open GitHub in Safari", "Open github.com in Safari", () => {
  macotron.url.open("https://github.com", "com.apple.Safari");
});
