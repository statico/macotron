// demo-datetime.js
// APIs: macotron.command, macotron.clipboard.set, macotron.notify

macotron.command("Insert ISO Date", "Copy current ISO-8601 timestamp to the clipboard", () => {
    const iso = new Date().toISOString();
    macotron.clipboard.set(iso);
    macotron.notify.show("ISO Date", iso);
});
