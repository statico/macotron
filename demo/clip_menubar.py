import sys; sys.path.insert(0, '.')
from drive import *
# A still menu bar; the zoom and pan across it happen in the encode.
key('esc'); glide(1270, 790, 0.1)
p = record("menubar", 16)
done(p, "menubar")
c.disconnect()
