// APIs: url.open, command
macotron.plugin({
  title: "Safari",
  description: "Open a URL in Safari.",
});

macotron.command("Open GitHub in Safari", "Open github.com in Safari", () => {
  macotron.url.open("https://github.com", "com.apple.Safari");
});
