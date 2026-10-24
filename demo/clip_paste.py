import sys; sys.path.insert(0, '.')
from drive import *
# Clipboard History pastes a seeded entry into a TextEdit note, then the emoji
# picker inserts 🍷 after it. Run clean() first. Macotron keeps history in
# memory only, so after a restart the seeds are the whole list. In 1.0 a click
# puts the entry back on the clipboard and closes the panel; Cmd-V pastes it.
# ASCII only: tart exec mangles accents. The last seed is the top row, which
# puts Taberna third.
SEEDS = ["Pick up the Lisbon tram passes", "brew? No. Built-in macOS only.",
         "https://macotron.statico.io", "Lisbon trip: TP 238, departs 4:10 PM",
         'git commit -m "Ship the demo video"', "Taberna da Rua das Flores, 8 PM",
         "Tram 28 to Graca, then the miradouro", "Pasteis de Belem at 4"]
vm("; ".join(f"printf %s '{s}' | pbcopy; sleep 1.2" for s in SEEDS))
vm("""osascript -e 'tell application "TextEdit"
close every window saving no
activate
set d to make new document with properties {text:"Friday in Lisbon" & return & return & "Dinner: "}
set size of text of d to 28
set bounds of front window to {240, 140, 1040, 600}
end tell'""")
key('esc'); glide(1100, 680, 0.1)
combo(CMD, 'down')
p = record("paste", 16)
combo(OPT, 'space'); time.sleep(0.7)
type_('clip'); time.sleep(0.9)
key('enter'); time.sleep(1.2)
click(520, 306, 0.8); time.sleep(0.5)  # "Taberna da Rua das Flores, 8 PM"
glide(1100, 680, 0.6)
combo(CMD, 'v'); time.sleep(1.0)
key('space')
combo(OPT, 'space'); time.sleep(0.7)
type_('emoji'); time.sleep(0.9)
key('enter'); time.sleep(1.6)
type_('wine'); time.sleep(1.6)
key('enter'); time.sleep(2.5)
done(p, "paste")
c.disconnect()
