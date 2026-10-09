"""Record clips in order, each on a clean desktop and a fresh track with
cover art. Community and meetings need their state reset first."""
import subprocess, sys
sys.path.insert(0, '.')
from drive import wait_art, clean, vm, c, _sleep
c.disconnect()
MENU = 'tell application "System Events" to tell process "Macotron" to click menu item "{}" of menu 1 of menu bar item 1 of menu bar 2'
for name in sys.argv[1:]:
    if name == "community":
        # Hot reload notices the deleted file; turn it back off so its
        # banner stays out of the Macotron menu.
        vm(f"osascript -e '{MENU.format('Enable Hot Reloading')}'; sleep 2; rm -f ~/Macotron/plugins/chess-puzzles.js; sleep 2; osascript -e '{MENU.format('Disable Hot Reloading')}'")
    wait_art(max_age=60)
    clean()
    if name == "meetings":
        subprocess.run("tart exec -i demo-gg osascript - < files/meet.applescript; tart exec demo-gg osascript -e 'quit app \"Calendar\"'", shell=True)
        _sleep(31)
    subprocess.run([sys.executable, "-W", "ignore", f"clip_{name}.py"], check=True)
