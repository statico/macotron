macotron.plugin({
  title: "Hyper Key",
  description: "Use Caps Lock as a Hyper key (Command, Shift, Control, and Option together).",
});

macotron.keyboard.setHyperKey("caps");
macotron.keyboard.on("Hyper H", "hyper+h", () => {
  macotron.notify.toast("Hyper", "Hyper+H");
});
