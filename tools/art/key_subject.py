#!/usr/bin/env python3
"""Keys a subject plate off its magenta ground and prints it onto the poster inks.

    uv run --with pillow --with numpy tools/art/key_subject.py raw/subject-toret_1.png out.png \
        [--height 512] [--drop notte] [--min-area 120]

The model is asked for one object on flat magenta (see generate.sh). Magenta is not
an ink and not in any of the object's colours, so the ground is everything pink
connected to the border. The object is cropped to its bounding box, scaled, moved
to the nearest ink in CIELAB (quantise.py), and saved as a palette PNG with a binary
alpha: no semi-transparent pixels, so nothing is ever blended on screen.
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import quantise as q  # noqa: E402


def ground_mask(img):
    """True where the pixel is magenta-ish and connected to the border."""
    hsv = np.asarray(img.convert("HSV")).astype(np.float64)
    hue, sat, val = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255, hsv[..., 2] / 255
    pink = (hue >= 290) & (hue <= 350) & (sat > 0.35) & (val > 0.45)
    h, w = pink.shape
    seen = np.zeros((h, w), bool)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if pink[y, x] and not seen[y, x]:
                seen[y, x] = True; queue.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if pink[y, x] and not seen[y, x]:
                seen[y, x] = True; queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and pink[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True; queue.append((ny, nx))
    return seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--height", type=int, default=512)
    ap.add_argument("--drop", default="notte")
    ap.add_argument("--min-area", type=int, default=120)
    ap.add_argument("--erode", type=int, default=2, help="pixels of fringe to shave off the cut-out edge")
    ap.add_argument("--outline", type=int, default=0,
                    help="pixels of inchiostro keyline added around the cut-out, so a cream basin "
                         "still reads on cream stock and a grey-green column on grey-green")
    a = ap.parse_args()

    img = Image.open(a.src).convert("RGB")
    ground = ground_mask(img)
    subject = ~ground
    ys, xs = np.where(subject)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    img, subject = img.crop(box), subject[box[1]:box[3], box[0]:box[2]]
    scale = a.height / img.height
    size = (round(img.width * scale), a.height)
    img = img.filter(ImageFilter.MedianFilter(5)).resize(size, Image.LANCZOS)
    mask = Image.fromarray((subject * 255).astype(np.uint8)).resize(size, Image.LANCZOS)
    for _ in range(a.erode):
        mask = mask.filter(ImageFilter.MinFilter(3))
    keep = np.asarray(mask) > 200

    if a.outline:
        n = a.outline
        keep = np.pad(keep, n)
        img = Image.fromarray(np.pad(np.asarray(img), ((n, n), (n, n), (0, 0)), mode="edge"))
        grown = Image.fromarray((keep * 255).astype(np.uint8))
        for _ in range(n):
            grown = grown.filter(ImageFilter.MaxFilter(3))
        ring = (np.asarray(grown) > 127) & ~keep
        keep = keep | ring
    else:
        ring = np.zeros_like(keep)

    inks = {k: v for k, v in q.INKS.items() if k not in a.drop.split(",")}
    names = list(inks)
    pal = np.array([q.rgb(inks[n]) for n in names], np.uint8)
    arr = np.asarray(img).copy()
    arr[~keep] = pal[names.index("carta")]  # keep the ground out of the vote
    arr[ring] = pal[names.index("inchiostro")]
    idx = ((q.to_lab(arr)[:, :, None, :] - q.to_lab(pal)[None, None]) ** 2).sum(-1).argmin(-1)
    idx = q.majority(idx, len(names), 2)
    idx = q.despeckle(idx, len(names), a.min_area)
    idx[ring] = names.index("inchiostro")
    rgba = np.zeros((*idx.shape, 4), np.uint8)
    rgba[..., :3] = pal[idx]
    rgba[..., 3] = np.where(keep, 255, 0)
    Image.fromarray(rgba).save(a.dst, optimize=True)
    used = {names[i]: round(float((idx[keep] == i).mean()) * 100, 1) for i in range(len(names)) if (idx[keep] == i).any()}
    print(a.dst, size, used)


if __name__ == "__main__":
    main()
