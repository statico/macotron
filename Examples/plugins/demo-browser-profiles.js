// APIs: url.open with profile, command
const chrome = "com.google.Chrome";

macotron.url.registerHandler("https");
macotron.url.on("https", "github.com", (event) => {
  macotron.url.open(event.url, chrome, "Profile 1");
});

macotron.command("Open GitHub (Chrome Profile 1)", "Open github.com in Chrome Profile 1", () => {
  macotron.url.open("https://github.com", chrome, "Profile 1");
});
