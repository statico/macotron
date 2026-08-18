macotron.requirePermissions(["screenRecording"]);

macotron.keyboard.on("cmd+shift+o", async () => {
    if (!macotron.screen || !macotron.screen.capture) {
        macotron.notify.show("OCR", "Call macotron.ocr.recognize({ path: \"/path/to/image.png\" })");
        return;
    }

    try {
        const text = await macotron.ocr.recognize({ image: await macotron.screen.capture() });
        macotron.clipboard.set(text);
        macotron.notify.show("OCR", text || "No text found");
    } catch (error) {
        macotron.notify.show("OCR failed", String(error));
    }
});
