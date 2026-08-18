macotron.on("app:activated", (app) => {
  macotron.notify.show("App activated", app.name);
});
