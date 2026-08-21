const opts = macotron.plugin({
  title: "World Clock",
  description: "Show the time in several cities in the menu bar.",
  options: {
    zones: {
      type: "string",
      label: "Time zones (IANA, space-separated)",
      default: "America/Los_Angeles America/New_York Europe/London UTC",
    },
  },
});

function zones() {
  return String(opts.zones || "").split(/\s+/).filter(Boolean);
}

function zoneLabel(zone) {
  return String(zone).split("/").pop().replace(/_/g, " ");
}

function formatTime(now, zone) {
  try {
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: zone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(now);
  } catch (_) {
    return "";
  }
}

async function paint() {
  const now = new Date();
  for (const zone of zones()) {
    let title = formatTime(now, zone);
    if (!title) {
      const r = await macotron.shell.run("/usr/bin/env", ["TZ=" + zone, "/bin/date", "+%H:%M"]);
      title = String((r && r.stdout) || "").trim();
    }
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
