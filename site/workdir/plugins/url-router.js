// APIs: url.registerHandler, url.on, url.open, command
macotron.plugin({
  title: "URL Router",
  description: "Open YouTube links in Safari.",
});

macotron.url.registerHandler("https");

macotron.url.on("https", "youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.url.on("https", "www.youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.command("Open YouTube in Safari", "Open youtube.com via the URL router", () => {
    macotron.url.open("https://www.youtube.com", "com.apple.Safari");
});
