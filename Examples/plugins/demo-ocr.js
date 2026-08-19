// APIs: ocr.recognize, screen.capture, clipboard.set, command
macotron.requirePermissions(["screenRecording"]);

async function ocrScreen() {
    try {
        const text = await macotron.ocr.recognize({ image: await macotron.screen.capture() });
        macotron.clipboard.set(text);
        macotron.notify.show("OCR", text || "No text found");
    } catch (error) {
        macotron.notify.show("OCR failed", String(error));
    }
}

macotron.keyboard.on("ocr", "cmd+shift+o", ocrScreen);
macotron.command("OCR Screen", "Capture screen, OCR text, copy to clipboard", ocrScreen);
