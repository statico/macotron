import sys; sys.path.insert(0, '.')
from drive import *
key('esc'); glide(800, 300, 0.1)
p = record("system", 30)
subprocess.Popen(["tart", "exec", VM, "bash", "-c", "for i in 1 2 3; do perl -e 'alarm 18; 1 while 1' & done; wait"])
time.sleep(0.2)
# CPU graph, battery, weather, calendar: each a left-click menu.
for x, hold in [(1035, 2.6), (970, 2.2), (902, 2.6), (846, 3.4)]:
    glide(x, 12, 0.9); time.sleep(0.3)
    c.mouseDown(1); time.sleep(0.2); c.mouseUp(1)
    time.sleep(hold)
    key('esc'); time.sleep(0.3)
glide(760, 340, 0.9)
done(p, "system")
c.disconnect()
