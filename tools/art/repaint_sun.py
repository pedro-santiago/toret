#!/usr/bin/env python3
"""Replaces a wobbly generated sun with an exact disc, on an already-quantised image.

    uv run --with pillow --with numpy tools/art/repaint_sun.py in.png out.png \
        --sun cx,cy,r [--dot cx,cy,r] [--sky-below y]

Diffusion models draw suns as blobs. Everything that is *sky* (cream or yellow,
above --sky-below) is reset to cream, then a true circle of sun-yellow is laid
over the sky only, so mountains and roofs in front of it stay in front. The
optional red dot is drawn last, over the sky, like the poster's.
"""
import argparse
import numpy as np
from PIL import Image

CARTA, SOLE, ROSSO = (0xF0, 0xE3, 0xBF), (0xE9, 0xB3, 0x3B), (0xB7, 0x30, 0x1F)

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--sun", required=True)
ap.add_argument("--dot")
ap.add_argument("--sky-below", type=int, default=10**9, help="only pixels above this row count as sky")
a = ap.parse_args()

img = np.array(Image.open(a.src).convert("RGB"))
h, w, _ = img.shape
yy, xx = np.mgrid[0:h, 0:w]
sky = ((img == CARTA).all(-1) | (img == SOLE).all(-1) | (img == ROSSO).all(-1)) & (yy < a.sky_below)
img[sky] = CARTA
for spec, colour in ((a.sun, SOLE), (a.dot, ROSSO)):
    if not spec:
        continue
    cx, cy, r = (float(v) for v in spec.split(","))
    disc = (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r
    img[disc & sky] = colour
Image.fromarray(img).save(a.dst, optimize=True)
print(a.dst)
