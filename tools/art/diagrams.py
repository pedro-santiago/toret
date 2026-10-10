#!/usr/bin/env python3
"""Draws the README diagrams and banner as SVG, in the poster's own inks.

    uv run --with fonttools --with resvg_py tools/art/diagrams.py [art.png]

Every letter is converted to an outline from the bundled font files
(Toret/Resources/Fonts), so the SVGs look the same on GitHub, in Preview and in
a browser with none of those fonts installed. Shapes are exact, not generated.

Writes docs/images/architecture.svg, data-flow.svg and banner.svg (+ banner.png).
"""
import base64
import os
import sys
from functools import lru_cache

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
FONTS = os.path.join(ROOT, "Toret", "Resources", "Fonts")
OUT = os.path.join(ROOT, "docs", "images")

CARTA, CHIARA, SCURA = "#F0E3BF", "#F7EDD0", "#E3D3A5"
INK, SOLE, ROSSO, BLU = "#16130F", "#E9B33B", "#B7301F", "#2C61A0"
SALVIA, SALVIA_D, FACCIATA = "#8CA48F", "#5C7864", "#D9C79A"


@lru_cache(maxsize=None)
def font(file, wght, wdth=None):
    f = TTFont(os.path.join(FONTS, file))
    axes = {"wght": wght}
    if wdth is not None:
        axes["wdth"] = wdth
    return instancer.instantiateVariableFont(f, axes, inplace=False)


def text_width(s, file, wght, size, wdth=None, tracking=0.0):
    f = font(file, wght, wdth)
    cmap, hmtx, upm = f.getBestCmap(), f["hmtx"], f["head"].unitsPerEm
    return sum(hmtx[cmap[ord(c)]][0] for c in s if ord(c) in cmap) * size / upm + tracking * size * len(s)


GLYPHS = {}  # (file, wght, wdth, glyph) -> (id, path data); emitted once in <defs>


def text(x, y, s, size, fill=INK, face="body", wght=None, anchor="start", tracking=0.0):
    """Outlined text. face: 'display' (League Spartan) or 'body' (Archivo)."""
    file, wd = ("LeagueSpartan.ttf", None) if face == "display" else ("Archivo.ttf", 100)
    wght = wght or (900 if face == "display" else 400)
    f = font(file, wght, wd)
    gs, cmap, hmtx, upm = f.getGlyphSet(), f.getBestCmap(), f["hmtx"], f["head"].unitsPerEm
    scale = size / upm
    width = text_width(s, file, wght, size, wd, tracking)
    cursor = {"start": 0, "middle": -width / 2, "end": -width}[anchor]
    parts = []
    for ch in s:
        if ord(ch) not in cmap:
            continue
        name = cmap[ord(ch)]
        key = (file, wght, wd, name)
        if key not in GLYPHS:
            pen = SVGPathPen(gs, ntos=lambda v: f"{v:.0f}")
            gs[name].draw(pen)
            GLYPHS[key] = (f"g{len(GLYPHS)}", pen.getCommands())
        gid, d = GLYPHS[key]
        if d:
            parts.append(
                f'<use href="#{gid}" transform="translate({x + cursor:.1f} {y:.1f}) scale({scale:.4f} {-scale:.4f})"/>'
            )
        cursor += hmtx[name][0] * scale + tracking * size
    return f'<g fill="{fill}">{"".join(parts)}</g>'


def lines(x, y, rows, size=20, fill=INK, leading=1.45, **kw):
    return "".join(text(x, y + i * size * leading, r, size, fill, **kw) for i, r in enumerate(rows))


def rect(x, y, w, h, fill="none", stroke=INK, sw=3):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'


def arrow(x1, y1, x2, y2, color=INK, dashed=False, sw=3):
    import math
    ang = math.atan2(y2 - y1, x2 - x1)
    hx, hy = x2 - 14 * math.cos(ang), y2 - 14 * math.sin(ang)
    px, py = 7 * math.sin(ang), -7 * math.cos(ang)
    dash = ' stroke-dasharray="10 8"' if dashed else ""
    return (f'<line x1="{x1}" y1="{y1}" x2="{hx:.1f}" y2="{hy:.1f}" stroke="{color}" stroke-width="{sw}"{dash}/>'
            f'<polygon points="{x2},{y2} {hx + px:.1f},{hy + py:.1f} {hx - px:.1f},{hy - py:.1f}" fill="{color}"/>')


def stripes(x, y, w, h, bands=4):
    band = h / bands
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{BLU}"/>']
    for i in range(1, bands):
        out.append(f'<rect x="{x}" y="{y + band * i - 2}" width="{w}" height="4" fill="{CARTA}"/>')
    return "".join(out)


def svg(width, height, body, title, desc):
    defs = "".join(f'<path id="{gid}" d="{d}"/>' for gid, d in GLYPHS.values() if d)
    GLYPHS.clear()
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
            f'role="img" aria-labelledby="t d"><title id="t">{title}</title><desc id="d">{desc}</desc>'
            f'<defs>{defs}</defs><rect width="{width}" height="{height}" fill="{CARTA}"/>{body}</svg>')


def heading(x, y, rows, size):
    """Poster title: stacked display lines with the vertical rule on the left."""
    body = f'<rect x="{x}" y="{y - size * 0.78}" width="4" height="{size * 0.8 * len(rows) + size * 0.04}" fill="{INK}"/>'
    for i, r in enumerate(rows):
        body += text(x + size * 0.2, y + i * size * 0.8, r.upper(), size, INK, "display", 900, tracking=-0.01)
    return body


def box(x, y, w, h, title, rows, fill=CHIARA, accent=None, title_size=26, row_size=18):
    out = rect(x, y, w, h, fill)
    if accent:
        out += f'<rect x="{x}" y="{y}" width="{w}" height="12" fill="{accent}"/>'
    out += text(x + 20, y + 52, title, title_size, INK, "display", 800)
    out += lines(x + 20, y + 86, rows, row_size, INK, face="body", wght=500)
    return out


# --------------------------------------------------------------------------- architecture

def architecture():
    b = heading(60, 130, ["Architecture"], 78)
    b += text(60, 178, "One Swift codebase, three targets, no server of ours.", 22, INK, wght=500)

    # Targets: widgets left, the app in the middle, the services it talks to on the right
    b += box(60, 230, 440, 300, "ToretWidgets", [
        "Home and Lock Screen widgets",
        "Controls: Control Center,",
        "Action Button",
        "Live Activity and Dynamic Island",
        "Reads its own location, falls back",
        "to the app's last published fix",
    ], accent=SOLE)
    b += box(540, 230, 560, 300, "Toret", [
        "Screens: Map, Nearby, Saved, Community,",
        "Settings, Compass, Detail, Route",
        "State: ToretModel, LocationProvider,",
        "ProximityAlerts, BackgroundLocation",
        "Community: store, LocalBackend,",
        "CloudKitBackend",
        "Intents: Siri, Shortcuts, Spotlight",
    ], accent=BLU)
    b += box(1140, 230, 400, 140, "Apple MapKit", ["Basemap and walking routes"], accent=SALVIA)
    b += box(1140, 390, 400, 140, "CloudKit public database",
             ["Community reports, Release builds only"], accent=SALVIA)
    b += arrow(1140, 300, 1102, 300, dashed=True)
    b += arrow(1140, 460, 1102, 460, dashed=True)

    # Shared
    b += rect(60, 590, 1040, 230, SCURA)
    b += text(80, 636, "Shared", 30, INK, "display", 900)
    b += text(210, 636, "compiled into the app and the widget extension", 20, INK, wght=500)
    b += box(80, 660, 330, 140, "Model", ["Fountain, Catalogue, Report,", "Bearing, Landmark, DeepLink"],
             title_size=22, row_size=17)
    b += box(430, 660, 330, 140, "Design system", ["Palette, Typo, Poster shapes,", "Motion"],
             title_size=22, row_size=17)
    b += box(780, 660, 300, 140, "Catalogue", ["fountains.json", "723 points from OSM"],
             title_size=22, row_size=17)
    b += arrow(280, 530, 280, 590)
    b += arrow(820, 530, 820, 590)

    # App group strip: label above, river below
    b += text(60, 842, "App Group: preferences, saved fountains, last published fix", 21, INK, wght=600)
    b += stripes(60, 856, 1040, 48)

    # Build-time source, and the tests
    b += box(1140, 590, 400, 140, "OpenStreetMap", ["ODbL, read once at build time", "by tools/build-catalogue.py"],
             accent=SALVIA)
    b += arrow(1140, 700, 1082, 700, dashed=True)
    b += box(1140, 750, 400, 150, "ToretTests", ["Swift Testing: catalogue,", "bearings, filters, model,",
                                                  "community, preferences, bridge"], accent=SALVIA)

    b += f'<rect x="60" y="935" width="1480" height="3" fill="{INK}"/>'
    b += text(1540, 975, "TORINO", 24, INK, "display", 800, anchor="end", tracking=0.08)
    b += text(60, 975, "Dashed lines leave the device. Everything else stays on it.", 20, INK, wght=500)
    return svg(1600, 1000, b, "Toret architecture",
               "The Toret app and the widget extension share one Swift module of models, design system and a "
               "bundled catalogue of fountains, and talk through an app group. OpenStreetMap feeds the catalogue "
               "at build time, MapKit draws the map, and CloudKit stores community reports.")


# --------------------------------------------------------------------------- data flow

def data_flow():
    b = heading(60, 130, ["Where the", "data comes from"], 70)
    b += text(60, 300, "Positions are real. The water state is only what people report.", 22, INK, wght=500)

    # Top lane: catalogue
    b += text(60, 360, "Positions", 30, INK, "display", 900)
    b += box(60, 384, 330, 150, "OpenStreetMap", ["amenity = drinking_water", "inside Turin, read via Overpass"],
             title_size=24, row_size=17, accent=SALVIA)
    b += box(470, 384, 330, 150, "build-catalogue.py", ["Names each point by its street", "and neighbourhood, once"],
             title_size=24, row_size=17, accent=SOLE)
    b += box(880, 384, 330, 150, "fountains.json", ["723 fountains, 184 toret", "bundled, works offline"],
             title_size=24, row_size=17, accent=BLU)
    b += box(1290, 384, 250, 150, "The app", ["Distances and", "bearings, on device"],
             title_size=24, row_size=17, accent=ROSSO)
    for x in (390, 800, 1210):
        b += arrow(x, 459, x + 80, 459)

    # Bottom lane: community
    b += text(60, 640, "Water state", 30, INK, "display", 900)
    b += box(60, 664, 330, 150, "A person at the fountain", ["Rates it, says running,", "weak or dry, adds a note"],
             title_size=24, row_size=17, accent=ROSSO)
    b += box(470, 664, 330, 150, "Local store", ["A JSON file on the device,", "works with no iCloud"],
             title_size=24, row_size=17, accent=SOLE)
    b += box(880, 664, 330, 150, "CloudKit public DB", ["Anonymous handle, no name,", "no position, 140 characters"],
             title_size=24, row_size=17, accent=BLU)
    b += box(1290, 664, 250, 150, "Every pin", ["Reports older than", "36 h count as unknown"],
             title_size=24, row_size=17, accent=SALVIA)
    for x in (390, 800, 1210):
        b += arrow(x, 739, x + 80, 739)
    b += arrow(1415, 664, 1415, 534, dashed=True)

    b += text(60, 870, "Nothing here is a feed.", 26, INK, "display", 800)
    b += lines(60, 906, [
        "No public source publishes whether water is running, so the app does not claim to know.",
        "A fountain nobody has reported on recently says so, and is drawn as an empty ring.",
    ], 19, wght=500)
    b += f'<rect x="60" y="955" width="1480" height="3" fill="{INK}"/>'
    b += text(1540, 990, "ODbL for the positions, MIT for the code", 20, INK, wght=500, anchor="end")
    return svg(1600, 1030, b, "Toret data flow",
               "Fountain positions flow from OpenStreetMap through a build script into a bundled JSON file. "
               "Water state flows from people's reports through a local store and CloudKit's public database "
               "onto every pin, and expires after thirty-six hours.")


# --------------------------------------------------------------------------- banner

def b64(path):
    with open(path, "rb") as fh:
        return base64.b64encode(fh.read()).decode()


def banner(art=None):
    W, H = 1600, 640
    b = ""
    art_x = 1132  # the generated toret plate sits at the right, full height
    # Sun and red dot
    b += f'<circle cx="860" cy="250" r="200" fill="{SOLE}"/>'
    b += f'<circle cx="1050" cy="380" r="40" fill="{ROSSO}"/>'

    def poly(pts, c):
        return f'<polygon points="{" ".join(f"{x},{y}" for x, y in pts)}" fill="{c}"/>'
    # Alps, with a lit facet on each peak
    b += poly([(600, 640), (800, 320), (1000, 640)], SALVIA)
    b += poly([(800, 320), (1000, 640), (830, 640)], SALVIA_D)
    b += poly([(800, 320), (840, 392), (760, 392)], CHIARA)
    b += poly([(900, 640), (1060, 360), (1240, 640)], SALVIA)
    b += poly([(1060, 360), (1240, 640), (1090, 640)], SALVIA_D)
    # Arcade strip under a red roof, then the river
    b += f'<rect x="560" y="470" width="{art_x - 560}" height="34" fill="{ROSSO}"/>'
    b += f'<rect x="560" y="504" width="{art_x - 560}" height="90" fill="{FACCIATA}"/>'
    for i in range(9):
        x = 574 + i * 62
        b += f'<path d="M{x} 594 V548 a20 20 0 0 1 40 0 V594 Z" fill="{INK}"/>'
    b += stripes(560, 594, art_x - 560, 46)
    if art:
        b += (f'<image x="{art_x}" y="0" width="{W - art_x}" height="{H}" preserveAspectRatio="xMidYMid slice" '
              f'href="data:image/png;base64,{b64(art)}"/>')
        b += f'<rect x="{art_x}" y="0" width="5" height="{H}" fill="{INK}"/>'
    # Type
    b += f'<rect x="60" y="60" width="5" height="520" fill="{INK}"/>'
    b += text(90, 270, "TORET", 215, INK, "display", 900, tracking=-0.02)
    b += text(94, 340, "Turin's public drinking fountains", 36, INK, wght=600)
    b += text(94, 392, "Find the nearest one with a compass.", 28, INK, wght=400)
    b += text(94, 470, "ITALY", 34, ROSSO, "display", 800, tracking=0.06)
    b += f'<rect x="60" y="600" width="480" height="4" fill="{INK}"/>'
    # Chequered diamond
    cx, cy, s = 120, 534, 24
    b += (f'<g transform="rotate(45 {cx} {cy})"><rect x="{cx - s * 1.5}" y="{cy - s * 1.5}" width="{s * 3}" height="{s * 3}" fill="{CHIARA}"/>')
    for r in range(3):
        for c in range(3):
            fill = SALVIA if (r, c) == (1, 1) else (ROSSO if (r + c) % 2 else CHIARA)
            b += f'<rect x="{cx - s * 1.5 + c * s}" y="{cy - s * 1.5 + r * s}" width="{s}" height="{s}" fill="{fill}"/>'
    b += f'<rect x="{cx - s * 1.5}" y="{cy - s * 1.5}" width="{s * 3}" height="{s * 3}" fill="none" stroke="{INK}" stroke-width="2.5"/></g>'
    return svg(W, H, b, "Toret", "A flat travel-poster banner: the word TORET in heavy black type beside a yellow sun, "
               "grey-green Alps, arcaded buildings under red roofs, a striped blue river and a cast-iron fountain "
               "with a bull's-head spout.")


def main():
    os.makedirs(OUT, exist_ok=True)
    art = sys.argv[1] if len(sys.argv) > 1 else None
    for name, content in (("architecture", architecture()), ("data-flow", data_flow()), ("banner", banner(art))):
        path = os.path.join(OUT, f"{name}.svg")
        open(path, "w").write(content)
        print("wrote", os.path.normpath(path))
    preview = os.environ.get("PREVIEW_DIR", "build/art")
    os.makedirs(preview, exist_ok=True)
    png(os.path.join(OUT, "banner.svg"), os.path.join(OUT, "banner.png"), 1600)
    for name in ("architecture", "data-flow"):
        png(os.path.join(OUT, f"{name}.svg"), os.path.join(preview, f"{name}.png"), 1600)


def png(svg_path, png_path, width):
    open(png_path, "wb").write(bytes(resvg_py.svg_to_bytes(svg_path=svg_path, width=width)))


if __name__ == "__main__":
    main()
