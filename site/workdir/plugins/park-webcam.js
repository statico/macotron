macotron.plugin({
    title: "Park Webcam",
    description: "Watch the Roosevelt Arch at Yellowstone live in the menu bar.",
    help: "Click the camera in the menu bar. The picture is the National Park Service webcam at the north entrance to Yellowstone, and refreshes itself every 15 seconds while the menu is open.",
});

// The park service posts a fresh frame every half minute or so. It is a plain
// JPEG, so the page just re-requests it with a new query string.
const CAM = "https://www.nps.gov/webcams-yell/mammoth_arch.jpg";
const PAGE = "https://www.nps.gov/yell/learn/photosmultimedia/webcams.htm";

const view = `<style>
body { display:flex; align-items:center; justify-content:center; }
img { width:100%; height:100%; object-fit:cover; border-radius:6px; }
#wait { position:absolute; opacity:0.6; }
</style>
<div id="wait">Loading…</div>
<img id="cam" alt="">
<script>
const img = document.getElementById("cam");
img.onload = () => document.getElementById("wait").remove();
const load = () => { img.src = "${CAM}?t=" + Date.now(); };
load();
setInterval(load, 15000);
</script>`;

macotron.menubar.status("park-webcam", {
    title: "",
    sfSymbol: "web.camera",
    menu: [
        { title: "Roosevelt Arch, Yellowstone" },
        { html: view, width: 320, height: 180 },
        "-",
        { title: "All park webcams…", onClick: () => macotron.url.open(PAGE) },
    ],
});
