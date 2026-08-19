// APIs: url.open, command
macotron.command("Open GitHub in Safari", "Open github.com in Safari", () => {
  macotron.url.open("https://github.com", "com.apple.Safari");
});
