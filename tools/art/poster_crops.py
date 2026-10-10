#!/usr/bin/env python3
"""Cuts the reference poster into the pieces the app prints, on the app's own inks.

    uv run --with pillow --with numpy tools/art/poster_crops.py <poster.png> <out-dir>

The poster is the design reference the app is drawn from. Each piece is a
rectangular crop with the title lettering painted out, then moved onto the nine
inks by tools/art/quantise.py, so the cream matches Palette.carta exactly and a
piece sits on a screen with no visible edge. The poster itself is not shipped.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

poster, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
CREAM = (240, 228, 194)

image = Image.open(poster).convert("RGB")
draw = ImageDraw.Draw(image)
# The title block and its rule: lettering is typography, and typography is Spartan's job.
draw.rectangle((0, 0, 566, 780), fill=CREAM)
draw.rectangle((0, 0, 58, image.height), fill=CREAM)
clean = os.path.join(out, "_clean.png")
image.save(clean)

def tidy_river(path):
    """The river's soft stripes quantise into green and beige speckle; it is all blue and cream.

    Everything in the river that is not a cream stripe or black becomes the river's blue.
    The bridge arch above it keeps its own beige and black.
    """
    import numpy as np
    pixels = np.array(Image.open(path).convert("RGB"))
    height, width, _ = pixels.shape
    top = int((1405 - 1304) * 2)
    left = int((722 - 58) * 2)
    region = pixels[top:, left:]
    ink = {name: np.array([(v >> 16) & 255, (v >> 8) & 255, v & 255]) for name, v in
           {"salvia": 0x8CA48F, "salviaScura": 0x5C7864, "facciata": 0xD9C79A, "blu": 0x2C61A0}.items()}
    for key in ("salvia", "salviaScura", "facciata"):
        region[(region == ink[key]).all(-1)] = ink["blu"]
    pixels[top:, left:] = region
    Image.fromarray(pixels).save(path)


PIECES = {
    # name: (left, top, right, bottom)
    "poster-mole": (566, 0, 1224, 1300),     # the spire, the sun, the red dot, the dome
    "poster-city": (58, 640, 1224, 1300),    # Alps, domes, arcades, the Mole's base, the rider
    "poster-alps": (58, 790, 600, 1135),     # the three peaks alone
    "poster-foot": (58, 1304, 1224, 1614),   # black triangle, chequers, red, blue, river, bridge
}
for name, box in PIECES.items():
    target = os.path.join(out, f"{name}.png")
    subprocess.run(
        [sys.executable, os.path.join(os.path.dirname(__file__), "quantise.py"), clean, target,
         "--crop", ",".join(map(str, box)), "--scale", "2"],
        check=True,
    )
    if name == "poster-foot":
        tidy_river(target)
    print(name, Image.open(target).size)
os.remove(clean)
