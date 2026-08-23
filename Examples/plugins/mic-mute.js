macotron.plugin({
  title: "Mic Mute",
  description: "Mute or unmute the microphone from the menu bar.",
  help: "Click the mic in the menu bar to mute or unmute the current input device.\n\n"
      + "Not every input device exposes a mute switch to macOS. This page reports whether "
      + "yours does.",
});

// Plenty of built-in and USB mics expose no settable mute property, and Core
// Audio just reports the write as failed. Writing back the value the device
// already has is a no-op that tells us which kind we have.
function probe() {
  const mic = macotron.audio.input();
  if (!mic) return { mic: null, controllable: false, message: "No input device" };
  const controllable = macotron.audio.setMuted(macotron.audio.isMuted(mic.id), mic.id);
  return {
    mic,
    controllable,
    message: controllable ? mic.name : mic.name + " has no mute control",
  };
}

function paint() {
  const state = probe();
  const muted = !!(state.mic && macotron.audio.isMuted(state.mic.id));
  macotron.menubar.status("mic", {
    title: "",
    sfSymbol: muted ? "mic.slash.fill" : "mic.fill",
    color: muted ? "red" : undefined,
    onClick: toggle,
  });
  macotron.checks([{ title: "Microphone", ok: state.controllable, message: state.message }]);
}

function toggle() {
  const state = probe();
  if (!state.controllable) {
    macotron.notify.toast("Mic", state.message, { color: "error" });
    paint();
    return;
  }
  const want = !macotron.audio.isMuted(state.mic.id);
  macotron.audio.setMuted(want, state.mic.id);
  if (macotron.audio.isMuted(state.mic.id) !== want) {
    macotron.notify.toast("Mic", state.mic.name + " refused the change", { color: "error" });
  }
  paint();
}

macotron.on("audio:changed", paint);
paint();
