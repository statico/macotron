macotron.plugin({
  title: "Calendar",
  description: "Show upcoming events.",
});

macotron.command("upcoming-events", "Show upcoming calendar events", () => {
  const events = macotron.calendar.upcoming({ hours: 24 });
  const body = events.slice(0, 5).map((event) => event.title).join(", ");
  macotron.notify.toast("Upcoming events", body || "No events in the next 24 hours");
});
