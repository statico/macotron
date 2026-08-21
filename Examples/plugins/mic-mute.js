macotron.plugin({
  title: "Mic Mute",
  description: "Mute or unmute the microphone from the menu bar.",
});

function paint() {
  const mic = macotron.audio.input();
  const muted = !!(mic && macotron.audio.isMuted(mic.id));
  macotron.menubar.status("mic", {
    title: "",
    sfSymbol: muted ? "mic.slash.fill" : "mic.fill",
    color: muted ? "red" : undefined,
    onClick: toggle,
  });
}

function toggle() {
  const mic = macotron.audio.input();
  if (!mic) return;
  macotron.audio.setMuted(!macotron.audio.isMuted(mic.id), mic.id);
  paint();
}

macotron.on("audio:changed", paint);
paint();
