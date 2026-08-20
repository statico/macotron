// APIs: ocr.recognize, screen.capture, clipboard.set, notify.toast, command
macotron.plugin({
  title: "OCR",
  description: "Select a screen area and copy the text.",
  permissions: ["screenRecording"],
});

async function ocrSelection() {
    macotron.notify.toast("Select the area of the screen you want to OCR", { duration: 4000 });
    try {
        const image = await macotron.screen.capture({ selection: true });
        if (!image) return;
        const text = await macotron.ocr.recognize({ image });
        if (!text) {
            macotron.notify.toast("No text found");
            return;
        }
        macotron.clipboard.set(text);
        macotron.notify.toast("Text copied to clipboard", { color: "success" });
    } catch (error) {
        macotron.notify.toast("OCR failed", String(error));
    }
}

macotron.keyboard.on("OCR", "cmd+shift+o", ocrSelection);
macotron.command("OCR Selection", "Drag a box, OCR the text, copy to clipboard", ocrSelection);
