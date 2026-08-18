// APIs: app:activated event, app.frontmost, command
macotron.on("app:activated", (app) => {
  macotron.notify.show("App activated", app.name);
});

macotron.command("Frontmost App", "Show the frontmost application", () => {
  const app = macotron.app.frontmost();
  macotron.notify.show("Frontmost", app ? `${app.name} (${app.bundleID})` : "None");
});
