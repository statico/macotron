macotron.plugin({
  title: "Audio Menu Bar Widgets",
  description: "Switch speakers and mute volume from the menu bar.",
});

function outputs() {
  return macotron.audio.devices().filter((d) => d.output);
}

function clip(name) {
  name = name || "Audio";
  return name.length > 15 ? name.slice(0, 14) + "…" : name;
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
macotron.command("Cycle Output", "Switch to the next audio output", cycle);
macotron.command("Mute", "Mute or unmute the system output", mute);
