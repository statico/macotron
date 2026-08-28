macotron.plugin({
  title: "Upcoming Events Example",
  description: "Show your upcoming calendar events.",
});

macotron.command("Upcoming Events", "Show upcoming calendar events", async () => {
  const events = await macotron.calendar.upcoming({ hours: 24 });
  const body = events.slice(0, 5).map((event) => event.title).join(", ");
  macotron.notify.toast("Upcoming events", body || "No events in the next 24 hours");
});
