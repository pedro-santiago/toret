#!/usr/bin/env python3
"""Prints a generated image onto the poster's inks.

    uv run --with pillow --with numpy tools/art/quantise.py in.png out.png \
        [--crop L,T,R,B] [--scale 2] [--palette core|extra] [--mode 2]

A diffusion model paints in a thousand near-colours; the app prints in nine.
Every pixel is moved to the nearest ink in CIELAB, after a light median denoise,
and a majority filter then removes the single-pixel speckle that quantising
leaves along soft edges, so the result is flat colour with crisp boundaries.
"""
import argparse
import numpy as np
from PIL import Image, ImageFilter

INKS = {
    "carta": 0xF0E3BF, "inchiostro": 0x16130F, "sole": 0xE9B33B, "rosso": 0xB7301F,
    "blu": 0x2C61A0, "salvia": 0x8CA48F, "salviaScura": 0x5C7864,
    "facciata": 0xD9C79A, "notte": 0x12161C,
}
EXTRA = {"cartaChiara": 0xF7EDD0}


def rgb(hex_):
    return ((hex_ >> 16) & 255, (hex_ >> 8) & 255, hex_ & 255)


def to_lab(arr):
    """sRGB uint8 (..., 3) -> CIELAB float."""
    c = arr.astype(np.float64) / 255
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def majority(idx, n, radius):
    """Replace each pixel by the most common ink in its (2r+1)^2 window."""
    h, w = idx.shape
    pad = np.pad(idx, radius, mode="edge")
    counts = np.zeros((n, h, w), np.int32)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            win = pad[dy:dy + h, dx:dx + w]
            for k in range(n):
                counts[k] += (win == k)
    return counts.argmax(0)


def despeckle(idx, n, min_area):
    """Merge every connected region smaller than min_area pixels into its surroundings.

    Quantising a soft edge leaves islands of the neighbouring ink; a printed poster
    has none. Regions are found by flood fill and re-inked with the most common ink
    on their border.
    """
    from collections import deque
    h, w = idx.shape
    seen = np.zeros((h, w), bool)
    out = idx.copy()
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0, x0]:
                continue
            colour = idx[y0, x0]
            queue, region, border = deque([(y0, x0)]), [], np.zeros(n, np.int64)
            seen[y0, x0] = True
            while queue:
                y, x = queue.popleft()
                region.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w:
                        if idx[ny, nx] == colour:
                            if not seen[ny, nx]:
                                seen[ny, nx] = True
                                queue.append((ny, nx))
                        else:
                            border[idx[ny, nx]] += 1
            if len(region) < min_area and border.sum():
                ys, xs = zip(*region)
                out[list(ys), list(xs)] = border.argmax()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    ap.add_argument("--crop", help="L,T,R,B in source pixels")
    ap.add_argument("--scale", type=float, default=2.0)
    ap.add_argument("--palette", choices=["core", "extra"], default="core")
    ap.add_argument("--mode", type=int, default=2, help="majority filter radius, 0 = off")
    ap.add_argument("--denoise", type=int, default=3, help="median size, 0 = off")
    ap.add_argument("--drop", default="", help="comma list of inks to exclude")
    ap.add_argument("--hue", action="append", default=[],
                    help="before quantising, paint pixels of a hue range an ink: 'H0-H1:Smin>ink' (hue in degrees)")
    ap.add_argument("--fix", action="append", default=[],
                    help="retouch a region after quantising: 'from[,from2]>to@x0,y0,x1,y1' in output pixels")
    ap.add_argument("--min-area", type=int, default=0, help="merge regions smaller than this many pixels")
    a = ap.parse_args()

    img = Image.open(a.src).convert("RGB")
    if a.crop:
        img = img.crop(tuple(int(v) for v in a.crop.split(",")))
    if a.denoise:
        img = img.filter(ImageFilter.MedianFilter(a.denoise))
    if a.scale != 1:
        img = img.resize((round(img.width * a.scale), round(img.height * a.scale)), Image.LANCZOS)

    for rule in a.hue:
        span, ink = rule.split(">")
        hues, smin = span.split(":")
        h0, h1 = (float(v) for v in hues.split("-"))
        hsv = np.asarray(img.convert("HSV")).astype(np.float64)
        hue, sat = hsv[..., 0] * 360 / 255, hsv[..., 1] / 255
        mask = (hue >= h0) & (hue <= h1) & (sat >= float(smin))
        arr = np.asarray(img).copy()
        arr[mask] = rgb(INKS[ink])
        img = Image.fromarray(arr)

    inks = dict(INKS)
    if a.palette == "extra":
        inks.update(EXTRA)
    for name in filter(None, a.drop.split(",")):
        inks.pop(name, None)
    names = list(inks)
    pal = np.array([rgb(inks[n]) for n in names], np.uint8)
    lab_pal = to_lab(pal)

    arr = np.asarray(img)
    lab = to_lab(arr)
    d = ((lab[:, :, None, :] - lab_pal[None, None, :, :]) ** 2).sum(-1)
    idx = d.argmin(-1)
    if a.mode:
        idx = majority(idx, len(names), a.mode)
    if a.min_area:
        idx = despeckle(idx, len(names), a.min_area)
    for fix in a.fix:
        rule, box = fix.split("@")
        src, dst = rule.split(">")
        x0, y0, x1, y1 = (int(v) for v in box.split(","))
        sources = [names.index(n) for n in src.split(",")]
        region = idx[y0:y1, x0:x1]
        region[np.isin(region, sources)] = names.index(dst)
    Image.fromarray(pal[idx]).save(a.dst, optimize=True)
    used = {names[i]: round(float((idx == i).mean()) * 100, 1) for i in range(len(names))}
    print(a.dst, Image.open(a.dst).size, used)


if __name__ == "__main__":
    main()
