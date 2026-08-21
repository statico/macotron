macotron.plugin({
  title: "Headphone Pause",
  description: "Pause media when headphones unplug.",
});

let last = macotron.audio.output();

macotron.on("audio:changed", (info) => {
  const flags = (info && info.flags) || [];
  if (flags.indexOf("output") < 0 && flags.indexOf("devices") < 0) return;
  const out = macotron.audio.output();
  const uid = out && out.uid;
  const prev = last && last.uid;
  const name = (last && last.name) || "";
  if (prev && uid !== prev && /headphone|airpods|beats/i.test(name)) {
    const now = macotron.media.nowPlaying();
    if (now && now.playing) macotron.media.playPause();
  }
  last = out;
});
