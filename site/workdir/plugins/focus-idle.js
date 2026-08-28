// APIs: app:activated event, app.frontmost, command
macotron.plugin({
  title: "Frontmost App Example",
  description: "Show the app in front and the last app you switched to.",
});

let lastActivated = null;

macotron.on("app:activated", (app) => {
  lastActivated = app.name;
});

macotron.command("Frontmost App", "Show the frontmost app and the last one activated", () => {
  const app = macotron.app.frontmost();
  const current = app ? `${app.name} (${app.bundleID})` : "None";
  macotron.notify.toast("Frontmost", lastActivated ? `${current} — last: ${lastActivated}` : current);
});
