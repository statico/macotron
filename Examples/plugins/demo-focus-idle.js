// APIs: app:activated event, app.frontmost, command
let lastActivated = null;

macotron.on("app:activated", (app) => {
  lastActivated = app.name;
});

macotron.command("Frontmost App", "Show the frontmost app and the last one activated", () => {
  const app = macotron.app.frontmost();
  const current = app ? `${app.name} (${app.bundleID})` : "None";
  macotron.notify.show("Frontmost", lastActivated ? `${current} — last: ${lastActivated}` : current);
});
