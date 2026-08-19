// clipboard image demo — APIs: history(), setImage(base64), paste(id), remove(id)
// history items: { id, text, kind: "text"|"image", ts }
macotron.plugin({
  title: "Clipboard Images",
  description: "Count and re-paste clipboard images.",
});

macotron.command("Clipboard Images", "Count image/text history and re-paste newest image", () => {
    const items = macotron.clipboard.history();
    const images = items.filter((i) => i.kind === "image");
    const texts = items.filter((i) => i.kind === "text");
    macotron.log(`images=${images.length} text=${texts.length}`);
    if (images[0]) macotron.clipboard.paste(images[0].id);
});
