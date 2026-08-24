const opts = macotron.plugin({
  title: "World Clock",
  description: "Show the time in several cities in the menu bar.",
  options: {
    zones: {
      type: "text",
      label: "Time zones",
      help: "One IANA name per line, such as America/New_York.",
      default: "America/Los_Angeles\nAmerica/New_York\nEurope/London\nUTC",
    },
  },
});

function zones() {
  return String(opts.zones || "").split(/\s+/).filter(Boolean);
}

function zoneLabel(zone) {
  return String(zone).split("/").pop().replace(/_/g, " ");
}

function paint() {
  for (const zone of zones()) {
    // QuickJS has no Intl, so the zone conversion belongs to the host.
    const title = macotron.system.timeIn(zone);
    if (!title) continue;
    macotron.menubar.status("clock-" + zone, {
      title: title,
      subtitle: zoneLabel(zone),
      secondary: true,
      minWidth: 48,
    });
  }
}

macotron.every(30_000, paint);
paint();
