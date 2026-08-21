macotron.plugin({
  title: "Record",
  description: "Record the microphone, or preview and snapshot the camera.",
  permissions: ["microphone", "camera"],
});

macotron.command("Start Recording", "Record the microphone to ~/Desktop/macotron.m4a", () => {
  if (!macotron.audio.record({ path: "~/Desktop/macotron.m4a" })) {
    macotron.notify.toast("Record", "Could not start", { color: "error" });
    return;
  }
  macotron.notify.toast("Record", "Recording…");
});

macotron.command("Stop Recording", "Stop the microphone recording", () => {
  const result = macotron.audio.stopRecord();
  if (!result) {
    macotron.notify.toast("Record", "Not recording");
    return;
  }
  macotron.notify.toast("Record", result.path + " (" + Math.round(result.seconds) + "s)", {
    color: "success",
  });
});

macotron.command("Camera Preview", "Show a live camera preview", () => {
  if (!macotron.camera.preview()) {
    macotron.notify.toast("Camera", "Could not start preview", { color: "error" });
  }
});

macotron.command("Camera Snapshot", "Copy a preview still to the clipboard", () => {
  const png = macotron.camera.snapshot();
  if (!png) {
    macotron.notify.toast("Camera", "Start the preview first");
    return;
  }
  macotron.clipboard.setImage(png);
  macotron.notify.toast("Camera", "Snapshot copied", { color: "success" });
});
