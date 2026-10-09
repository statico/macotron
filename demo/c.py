import sys, time; sys.path.insert(0, '.')
from drive import *
for xy in sys.argv[1:]:
    x, y = map(int, xy.split(','))
    glide(x, y, 0.2); c.mouseDown(1); time.sleep(0.15); c.mouseUp(1); time.sleep(1.5)
time.sleep(2); shot()
