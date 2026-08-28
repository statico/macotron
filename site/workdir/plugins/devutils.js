// APIs: command, clipboard.set, notify

macotron.plugin({
    title: "Dev Utils",
    description: "Copy a UUID, Unix time, Base64 text, or a decoded JWT.",
});

function copy(title, value) {
    macotron.clipboard.set(value);
    macotron.notify.toast("Copied", title, { color: "success" });
}

function uuid() {
    const bytes = Array.from({ length: 16 }, () => Math.floor(Math.random() * 256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function b64(text) {
    const bytes = [];
    for (let i = 0; i < text.length; i++) bytes.push(text.charCodeAt(i) & 0xff);
    let out = "";
    for (let i = 0; i < bytes.length; i += 3) {
        const n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
        out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
        out += i + 1 < bytes.length ? B64[(n >> 6) & 63] : "=";
        out += i + 2 < bytes.length ? B64[n & 63] : "=";
    }
    return out;
}

function b64decode(input) {
    const clean = input.replace(/[^A-Za-z0-9+/=]/g, "");
    let out = "";
    for (let i = 0; i < clean.length; i += 4) {
        const n = (B64.indexOf(clean[i]) << 18) | (B64.indexOf(clean[i + 1]) << 12)
            | ((B64.indexOf(clean[i + 2]) & 63) << 6) | (B64.indexOf(clean[i + 3]) & 63);
        out += String.fromCharCode((n >> 16) & 255);
        if (clean[i + 2] !== "=") out += String.fromCharCode((n >> 8) & 255);
        if (clean[i + 3] !== "=") out += String.fromCharCode(n & 255);
    }
    return out;
}

macotron.command("Generate UUID", "Copy a random UUID v4", () => copy("UUID", uuid()));
macotron.command("Unix Timestamp", "Copy seconds since epoch", () => copy("Timestamp", String(Math.floor(Date.now() / 1000))));
macotron.command("Encode Base64", "Base64-encode the current clipboard", () => {
    const text = macotron.clipboard.text();
    if (!text) {
        macotron.notify.toast("Encode Base64", "Clipboard is empty");
        return;
    }
    copy("Base64", b64(text));
});
macotron.command("Decode JWT", "Decode the clipboard JWT payload", () => {
    const token = macotron.clipboard.text().trim();
    const parts = token.split(".");
    if (parts.length < 2) {
        macotron.notify.toast("Decode JWT", "Clipboard is not a JWT");
        return;
    }
    let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (payload.length % 4) payload += "=";
    try {
        const json = JSON.stringify(JSON.parse(b64decode(payload)), null, 2);
        copy("JWT payload", json);
    } catch (err) {
        macotron.notify.toast("Decode JWT", String(err), { color: "failure" });
    }
});
