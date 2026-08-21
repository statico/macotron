macotron.plugin({
  title: "Hyper Key",
  description: "Hold Caps Lock as Hyper (⌘⇧⌃⌥).",
});

macotron.keyboard.setHyperKey("caps");
macotron.keyboard.on("Hyper H", "hyper+h", () => {
  macotron.notify.toast("Hyper", "Hyper+H");
});
