macotron.plugin({
  title: "Audio",
  description: "Cycle the default output device.",
});

function outputs() {
  return macotron.audio.devices().filter((d) => d.output);
}

function paint() {
  const out = macotron.audio.output();
  macotron.menubar.status("audio", {
    title: out ? out.name : "Audio",
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

macotron.on("audio:changed", paint);
paint();
macotron.command("Cycle Output", "Switch to the next audio output", cycle);
