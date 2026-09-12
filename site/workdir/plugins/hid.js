macotron.plugin({
  title: "HID (USB) Example",
  description: "List keyboards, mice, and other input devices on this Mac.",
});

macotron.command("HID Devices", "List attached HID devices", () => {
  const rows = macotron.hid.list();
  const names = rows
    .map((d) => d.name + " (" + hex(d.vendorID) + "/" + hex(d.productID) + ")")
    .join(", ") || "None";
  macotron.notify.toast("HID", names);
});

function hex(n) {
  return n.toString(16).padStart(4, "0");
}

// Pointer tuning has to come from the global defaults domain, not from
// hidutil: on real hardware `hidutil property --get` answers (null) for the
// acceleration keys, so defaults holds the only copy anyone can read back.
const POINTER_KEYS = [
  { key: "com.apple.mouse.scaling", label: "Mouse speed" },
  { key: "com.apple.trackpad.scaling", label: "Trackpad speed" },
  { key: "com.apple.scrollwheel.scaling", label: "Scroll speed" },
];

async function readScaling(key) {
  const r = await macotron.shell.run("/usr/bin/defaults", ["read", "-g", key]);
  // Nobody has to have ever changed these, and an absent key makes defaults
  // exit non-zero. That is "system default", not a failure to report.
  if (r.exitCode !== 0) return null;
  const n = Number(String(r.stdout).trim());
  return Number.isFinite(n) ? n : null;
}

function describeScaling(value) {
  if (value === null) return "system default";
  // -1 is the one value that is a mode rather than a speed: the mouse key
  // uses it to mean pointer acceleration is switched off altogether.
  if (value === -1) return "acceleration off";
  return String(value);
}

macotron.command("Pointer Tuning", "View and adjust pointer and scroll behavior", async () => {
  const values = [];
  for (const k of POINTER_KEYS) values.push(await readScaling(k.key));
  // swipescrolldirection is stored as 0/1, and absent means on, which is the
  // macOS default.
  const natural = (await readScaling("com.apple.swipescrolldirection")) !== 0;

  const rows = POINTER_KEYS.map((k, i) => `
    <div>
      <label>${k.label} — <span class="muted mono" id="v${i}">${describeScaling(values[i])}</span></label>
      <input type="range" min="0" max="3" step="0.125"
             value="${values[i] === null || values[i] < 0 ? 1 : values[i]}"
             oninput="setScaling(${i}, this.value)">
    </div>`).join("");

  const id = macotron.panel.open({
    title: "Pointer Tuning",
    width: 380,
    height: 320,
    html: `<div class="grow scroll">
${rows}
<div><label><input type="checkbox" ${natural ? "checked" : ""} onchange="setNatural(this.checked)"> Natural scrolling</label></div>
<div class="muted">Saved right away, but macOS only picks these up at your next
login, or when the device reconnects — so the pointer will not change speed
under your hand.</div>
</div>
<button onclick="close()">Close</button>
<script>
  const KEYS = ${JSON.stringify(POINTER_KEYS.map((k) => k.key))};
  function send(msg) { webkit.messageHandlers.macotron.postMessage(msg); }
  function setScaling(i, value) {
    // Echo the new number locally rather than asking the host to read it
    // back: defaults has already been written by the time it could answer.
    document.getElementById("v" + i).textContent = value;
    send({ key: KEYS[i], value: Number(value) });
  }
  function setNatural(on) { send({ key: "com.apple.swipescrolldirection", bool: on }); }
</script>`,
  });

  macotron.panel.onMessage(id, async (msg) => {
    const args = msg.bool === undefined
      ? ["write", "-g", msg.key, "-float", String(msg.value)]
      : ["write", "-g", msg.key, "-bool", msg.bool ? "true" : "false"];
    await macotron.shell.run("/usr/bin/defaults", args);
  });
});
