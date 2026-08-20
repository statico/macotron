macotron.plugin({
  title: "QR Code",
  description: "Scan a QR code from the screen or camera, or show one.",
  permissions: ["screenRecording", "camera"],
});

async function scanScreen() {
  macotron.notify.toast("Select the QR code", { duration: 3000 });
  const text = await macotron.qr.scan({ screenshot: true });
  if (!text) return;
  macotron.clipboard.set(text);
  macotron.notify.toast("QR copied", text, { color: "success" });
}

async function scanCamera() {
  const text = await macotron.qr.scan({ camera: true });
  if (!text) return;
  macotron.clipboard.set(text);
  macotron.notify.toast("QR copied", text, { color: "success" });
}

function showQR() {
  const text = macotron.clipboard.text() || macotron.prompt("Text for QR code");
  if (text) macotron.qr.show(text);
}

macotron.command("Scan QR from Screen", "Drag a box around a QR code and copy it", scanScreen);
macotron.command("Scan QR from Camera", "Point the camera at a QR code and copy it", scanCamera);
macotron.command("Show QR", "Show a QR code for the clipboard (or prompted text)", showQR);
