// APIs: screen.capture, panel, notify.toast, command
macotron.plugin({
  title: "Color Blindness Simulator",
  description: "Freeze the screen and repaint it the way a color blind viewer sees it.",
  help:
    "Runs the same way Color Oracle does: it takes one screenshot and shows the simulated copy full screen, so you can check a design without changing the display.\n\n" +
    "In the overlay, press 1 for deuteranopia, 2 for protanopia, 3 for tritanopia, or 4 for full color blindness. Escape or a click closes it. Only the main display is captured.",
  permissions: ["screenRecording"],
});

// Viénot, Brettel & Mollon (1999) dichromat matrices, applied to linear RGB —
// the same simulation Color Oracle uses. Grayscale is Rec. 709 luma.
const MODES = [
  { key: "deuteranopia", label: "Deuteranopia", hint: "green-blind, the common one",
    m: [0.29275, 0.70725, 0, 0.29275, 0.70725, 0, -0.02234, 0.02234, 1] },
  { key: "protanopia", label: "Protanopia", hint: "red-blind",
    m: [0.11238, 0.88762, 0, 0.11238, 0.88762, 0, 0.00401, -0.00401, 1] },
  { key: "tritanopia", label: "Tritanopia", hint: "blue-blind, rare",
    m: [1, 0.14461, -0.14461, 0, 1, 0, 0, 0.85164, 0.14836] },
  { key: "achromatopsia", label: "Achromatopsia", hint: "no color at all",
    m: [0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722] },
];

const PANEL_HTML = `<style>
html, body { margin:0; padding:0; overflow:hidden; background:#000; }
canvas { position:fixed; inset:0; width:100vw; height:100vh; }
#label { position:fixed; bottom:32px; left:50%; transform:translateX(-50%); z-index:1;
  font:600 15px -apple-system, system-ui; color:#fff; background:rgba(0,0,0,0.65);
  padding:10px 18px; border-radius:999px; backdrop-filter:blur(20px); white-space:nowrap; }
#label small { font-weight:400; opacity:0.7; margin-left:8px; }
</style>
<canvas id="c"></canvas>
<div id="label">Loading…</div>
<script>
let modes = [], src = null, ctx = null, mode = 0;
// sRGB transfer curves as tables: three pow() calls per pixel is seconds of work
// on a Retina screenshot, two lookups is milliseconds.
const TO_LINEAR = new Float32Array(256);
for (let i = 0; i < 256; i++) {
  const v = i / 255;
  TO_LINEAR[i] = v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}
// Indexed by sqrt(linear), not linear: sRGB is steep near black, so evenly
// spaced linear samples quantize the shadows into visible bands.
const STEPS = 1024;
const TO_SRGB = new Uint8ClampedArray(STEPS + 1);
for (let i = 0; i <= STEPS; i++) {
  const v = (i / STEPS) * (i / STEPS);
  TO_SRGB[i] = Math.round(255 * (v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055));
}
function encode(v) { return TO_SRGB[v <= 0 ? 0 : v >= 1 ? STEPS : (Math.sqrt(v) * STEPS + 0.5) | 0]; }

function render() {
  if (!src || !ctx) return;
  const m = modes[mode].m;
  const out = ctx.createImageData(src.width, src.height);
  const a = src.data, b = out.data;
  for (let i = 0; i < a.length; i += 4) {
    const r = TO_LINEAR[a[i]], g = TO_LINEAR[a[i + 1]], bl = TO_LINEAR[a[i + 2]];
    b[i] = encode(m[0] * r + m[1] * g + m[2] * bl);
    b[i + 1] = encode(m[3] * r + m[4] * g + m[5] * bl);
    b[i + 2] = encode(m[6] * r + m[7] * g + m[8] * bl);
    b[i + 3] = 255;
  }
  ctx.putImageData(out, 0, 0);
  document.getElementById("label").innerHTML =
    modes[mode].label + "<small>" + modes[mode].hint + " · 1-" + modes.length + " to switch · esc to close</small>";
}

window.__macotronReceive = (d) => {
  if (!d || !d.image) return;
  modes = d.modes;
  mode = d.mode;
  const img = new Image();
  img.onload = () => {
    const canvas = document.getElementById("c");
    canvas.width = img.width;
    canvas.height = img.height;
    ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);
    src = ctx.getImageData(0, 0, img.width, img.height);
    render();
  };
  img.src = "data:image/png;base64," + d.image;
};

document.onkeydown = (e) => {
  const n = Number(e.key);
  if (n >= 1 && n <= modes.length) { mode = n - 1; render(); }
};
document.onclick = () => close();
</script>`;

async function simulate(mode) {
  let image;
  try {
    image = await macotron.screen.capture();
  } catch (err) {
    macotron.notify.toast("Color blindness simulator", String(err), { color: "failure" });
    return;
  }
  if (!image) return;
  const id = macotron.panel.open({
    id: "color-blindness",
    title: "Color Blindness Simulator",
    fullscreen: true,
    frameless: true,
    html: PANEL_HTML,
  });
  macotron.panel.postMessage(id, { image, mode, modes: MODES });
}

for (let i = 0; i < MODES.length; i++) {
  const m = MODES[i];
  macotron.command(`Simulate ${m.label}`, `See the screen as a viewer with ${m.label.toLowerCase()} (${m.hint}) does`, () =>
    simulate(i)
  );
}
