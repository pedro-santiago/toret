#!/usr/bin/env python3
"""A seamless 512 px paper-grain overlay: faint fibres and speckle on transparency.

    uv run --with pillow --with numpy tools/art/paper_grain.py out.png

Laid over the cream stock at a few per cent it reads as printed paper rather than
as a screen. Everything wraps at the edges (the noise is filtered in the Fourier
domain), so it tiles without a seam, and the alpha is quantised to a few levels
so the PNG stays small.
"""
import sys
import numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(1961)  # the year of the Italia '61 expo in Turin


def wrapped_blur(a, sigma):
    f = np.fft.fft2(a)
    ky, kx = np.fft.fftfreq(a.shape[0])[:, None], np.fft.fftfreq(a.shape[1])[None, :]
    return np.real(np.fft.ifft2(f * np.exp(-2 * (np.pi * sigma) ** 2 * (kx ** 2 + ky ** 2))))


def norm(a):
    return (a - a.mean()) / a.std()


speckle = norm(wrapped_blur(rng.standard_normal((N, N)), 0.7))
cloud = norm(wrapped_blur(rng.standard_normal((N, N)), 14))
# Fibres: short random strokes, drawn wrapped.
fibres = np.zeros((N, N))
for _ in range(1400):
    x, y = rng.integers(0, N, 2)
    ang, length = rng.uniform(0, np.pi), rng.integers(3, 9)
    for t in range(length):
        fibres[int(y + t * np.sin(ang)) % N, int(x + t * np.cos(ang)) % N] = 1
fibres = wrapped_blur(fibres, 0.6)

field = 1.0 * speckle + 0.45 * cloud + 0.45 * norm(fibres)
dark = np.clip((field - 0.9) / 2.0, 0, 1)      # warm brown specks
light = np.clip((-field - 1.0) / 2.0, 0, 1)    # a few paler flecks
alpha_dark = (np.round(dark * 3) / 3 * 15).astype(np.uint8)
alpha_light = (np.round(light * 3) / 3 * 24).astype(np.uint8)

rgba = np.zeros((N, N, 4), np.uint8)
rgba[..., :3] = (0x6B, 0x4A, 0x1E)
rgba[..., 3] = alpha_dark
lit = alpha_light > alpha_dark
rgba[lit, :3] = (0xFF, 0xF6, 0xDA)
rgba[lit, 3] = alpha_light[lit]
Image.fromarray(rgba, "RGBA").save(sys.argv[1], optimize=True)
print(sys.argv[1], "dark px", round(float((alpha_dark > 0).mean()) * 100, 1), "%")
