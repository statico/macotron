// demo-url-router.js
// APIs: macotron.url.registerHandler, macotron.url.on, macotron.url.open

macotron.url.registerHandler("https");

macotron.url.on("https", "youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.url.on("https", "www.youtube.com", (event) => {
    macotron.url.open(event.url, "com.apple.Safari");
});

macotron.url.on("https", "*", (event) => {
    macotron.url.open(event.url, "company.thebrowser.Browser");
});
