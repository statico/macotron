const opts = macotron.plugin({
  title: "Audio Menu Bar Widgets",
  description: "Switch speakers and mute volume from the menu bar.",
  options: {
    showName: {
      type: "boolean",
      label: "Show the output device name in the menu bar",
      default: true,
    },
    maxLength: {
      type: "number",
      label: "Shorten the name to this many characters",
      default: 15,
    },
  },
});

function outputs() {
  return macotron.audio.devices().filter((d) => d.output);
}

// The icon carries the widget on its own, so hiding the name leaves the
// menu bar tidy rather than empty.
function clip(name) {
  if (!opts.showName) return "";
  const max = Math.max(1, Number(opts.maxLength) || 15);
  name = name || "Audio";
  return name.length > max ? name.slice(0, max - 1) + "…" : name;
}

function paint() {
  const out = macotron.audio.output();
  macotron.menubar.status("audio", {
    title: clip(out && out.name),
    sfSymbol: "speaker.wave.2",
    onClick: cycle,
  });
}

function cycle() {
  const list = outputs();
  if (!list.length) return;
  const current = macotron.audio.output();
  const i = Math.max(0, list.findIndex((d) => d.id === current?.id));
  const next = list[(i + 1) % list.length];
  macotron.audio.setOutput(next.id);
  macotron.notify.toast("Output", next.name);
}

function mute() {
  const on = !macotron.audio.isMuted();
  macotron.audio.setMuted(on);
  macotron.notify.toast("Volume", on ? "Muted" : "Unmuted");
}

macotron.on("audio:changed", paint);
paint();
macotron.keyboard.on("Cycle Output", "ctrl+opt+a", cycle);
macotron.command("Cycle Output", "Switch to the next audio output", cycle);
macotron.command("Mute", "Mute or unmute the system output", mute);
