"""Drive the demo VM over VNC and record clips. Coordinates are in points
(1280x800); VNC wants pixels, so everything is doubled here."""
import os, re, subprocess, sys, time
from vncdotool import api

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VM = os.environ.get("VM", "demo-gg")
log = open(f"{ROOT}/tmp/demo-vm.log").read()
PORT = re.search(r"127\.0\.0\.1:(\d+)", log).group(1)
PASS = re.search(r"vnc://:([^@]*)@", log).group(1)
c = api.connect(f"127.0.0.1::{PORT}", password=PASS)
pos = [640, 400]

# Every pause, glide and recording length runs at this fraction of what the
# clip scripts say, so the whole tour can be tightened in one place.
PACE = float(os.environ.get("PACE", "0.8"))
_sleep = time.sleep
time.sleep = lambda s: _sleep(s * PACE)


def vm(cmd):
    return subprocess.run(["tart", "exec", VM, "bash", "-c", cmd], capture_output=True, text=True).stdout


def glide(x, y, dur=0.6):
    """Ease the pointer to (x, y) so the recording shows motion, not a jump."""
    x0, y0 = pos
    steps = max(8, int(dur * 60))
    for i in range(1, steps + 1):
        t = i / steps
        e = t * t * (3 - 2 * t)
        c.mouseMove(int((x0 + (x - x0) * e) * 2), int((y0 + (y - y0) * e) * 2))
        time.sleep(dur / steps)
    pos[:] = [x, y]


def click(x=None, y=None, dur=0.6):
    if x is not None:
        glide(x, y, dur)
    c.mouseDown(1)
    time.sleep(0.08)
    c.mouseUp(1)


def drag(x, y, dur=1.0):
    c.mouseDown(1)
    time.sleep(0.15)
    glide(x, y, dur)
    time.sleep(0.25)
    c.mouseUp(1)


def key(k, hold=0.05):
    c.keyPress(k)
    time.sleep(hold)


def combo(*keys):
    """Hold modifiers explicitly; vncdotool's 'a-b' form is flaky here."""
    for k in keys:
        c.keyDown(k)
        time.sleep(0.04)
    for k in reversed(keys):
        c.keyUp(k)
        time.sleep(0.02)


def type_(text, gap=0.11):
    for ch in text:
        k = {" ": "space", "*": "shift-8", "+": "shift-="}.get(ch, ch)
        if k.startswith("shift-"):
            combo("shift", k[6:])
        else:
            c.keyPress(k)
        time.sleep(gap)


def record(name, seconds):
    """Start a background recording in the VM; call done() after."""
    vm(f"rm -f /tmp/{name}.mov")
    p = subprocess.Popen(["tart", "exec", VM, "screencapture", "-v", "-V", str(round(seconds * PACE)), "-C", "-x", f"/tmp/{name}.mov"])
    time.sleep(1.2)
    return p


def done(p, name):
    p.wait()
    vm(f'cp /tmp/{name}.mov "/Volumes/My Shared Files/share/{name}.mov"')
    print("saved", name)


def shot(path=f"{ROOT}/tmp/vm.png"):
    c.captureScreen(path)
    subprocess.run(["sips", "-Z", "1280", path, "--out", f"{ROOT}/tmp/vm-small.png"], capture_output=True)


if __name__ == "__main__":
    shot()

# Apple's VNC server swaps these: X11 Meta is Option, Alt is Command.
OPT, CMD = "meta", "alt"


def wait_art(max_age=90):
    """Block until Underground 80s has just started a track iTunes can match,
    so the Now Playing cover stays put for a whole clip. The page refreshes
    metadata every 20 s, so give the plugin that long to catch up."""
    import json, urllib.parse, urllib.request
    while True:
        song = json.load(urllib.request.urlopen("https://somafm.com/songs/u80s.json"))["songs"][0]
        age = time.time() - int(song["date"])
        term = urllib.parse.quote(f'{song["artist"]} {song["title"]}')
        hit = json.load(urllib.request.urlopen(f"https://itunes.apple.com/search?term={term}&entity=song&limit=1"))["resultCount"]
        print(f'{song["artist"]} - {song["title"]}: age {age:.0f}s, art {bool(hit)}', flush=True)
        if hit and 25 <= age <= max_age:
            return
        _sleep(10)


def clean():
    """Empty desktop for clips that aren't about windows: close Finder
    windows and hide every app but Finder and Macotron (Safari keeps playing)."""
    vm("""osascript -e 'tell application "Finder" to close every window' -e 'tell application "System Events" to set visible of (every process whose background only is false and name is not "Finder" and name is not "Macotron") to false' -e 'tell application "Finder" to activate'""")
    time.sleep(1)
