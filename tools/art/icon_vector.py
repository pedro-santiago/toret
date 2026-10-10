#!/usr/bin/env python3
"""A hand-drawn app-icon candidate: exact geometry, no diffusion.

    uv run --with resvg_py tools/art/icon_vector.py out.png [out.svg]

The poster's own parts at icon scale: the sun disc, the cast-iron column with a
bull's head (two horns, a brow, a spout), one blue drop, and the river stripes.
"""
import sys
import resvg_py

CARTA, INK, SOLE, BLU = "#F0E3BF", "#16130F", "#E9B33B", "#2C61A0"

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<rect width="1024" height="1024" fill="{CARTA}"/>
<circle cx="512" cy="450" r="340" fill="{SOLE}"/>
<!-- river -->
<rect x="0" y="790" width="1024" height="234" fill="{BLU}"/>
<rect x="0" y="854" width="1024" height="14" fill="{CARTA}"/>
<rect x="0" y="934" width="1024" height="14" fill="{CARTA}"/>
<!-- column: base, shaft, collar -->
<path d="M352 790 L372 730 H652 L672 790 Z" fill="{INK}"/>
<rect x="452" y="470" width="120" height="270" fill="{INK}"/>
<rect x="424" y="452" width="176" height="36" fill="{INK}"/>
<!-- bull's head: brow block, two crescent horns, muzzle with spout -->
<path d="M388 452 V318 Q388 282 424 282 H604 Q640 282 640 318 V452 Z" fill="{INK}"/>
<path d="M396 312 C340 306 318 262 326 214 C356 250 392 258 428 266 Z" fill="{INK}"/>
<path d="M628 312 C684 306 706 262 698 214 C668 250 632 258 596 266 Z" fill="{INK}"/>
<path d="M600 372 H700 Q742 372 742 408 Q742 440 700 440 H600 Z" fill="{INK}"/>
<!-- the drop -->
<path d="M716 456 C716 456 674 520 674 552 A42 42 0 0 0 758 552 C758 520 716 456 716 456 Z" fill="{BLU}"/>
<circle cx="512" cy="366" r="0" fill="{CARTA}"/>
</svg>'''

open(sys.argv[2] if len(sys.argv) > 2 else "/dev/null", "w").write(svg) if len(sys.argv) > 2 else None
open(sys.argv[1], "wb").write(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=1024, height=1024)))
print("wrote", sys.argv[1])
