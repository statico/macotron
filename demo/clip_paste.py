import sys; sys.path.insert(0, '.')
from drive import *
# Clipboard history (browse; filtering shows earlier takes' seeds), then the emoji picker inserting
# into a TextEdit note. 0.7.7's history panel doesn't paste on click here. Run
# clean() first. The seeds push older (and host-synced) entries off the list.
# ASCII only: tart exec mangles accents. The last seed is the top row.
SEEDS = ["Pick up the Lisbon tram passes", "brew? No. Built-in macOS only.",
         "https://macotron.statico.io", "Lisbon trip: TP 238, departs 4:10 PM",
         'git commit -m "Ship the demo video"', "Tram 28 to Graca, then the miradouro",
         "Pasteis de Belem at 4", "Taberna da Rua das Flores, 8 PM"]
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
p = record("paste", 14)
combo(OPT, 'space'); time.sleep(0.7)
type_('clip'); time.sleep(0.9)
key('enter'); time.sleep(1.4)
time.sleep(1.6)
key('esc'); time.sleep(0.6)
combo(OPT, 'space'); time.sleep(0.7)
type_('emoji'); time.sleep(0.9)
key('enter'); time.sleep(1.6)
type_('wine'); time.sleep(1.6)
key('enter'); time.sleep(2.5)
done(p, "paste")
c.disconnect()
