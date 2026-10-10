#!/usr/bin/env python3
"""Cuts the reference poster into transparent depth layers for the parallax scene.

    uv run --with pillow --with numpy --with scipy tools/art/poster_layers.py \
        <poster.png> <out-dir> [--debug]

The poster is the design reference the app is drawn from. Each layer is a crop of it
printed onto the app's nine inks (tools/art/quantise.py), with the title lettering and
the left rule painted out, and a hard alpha taken from the ink map, so edges are crisp
and there is no halo to fringe against a different background. Layers are cut at 2x.
The raw poster is never shipped.

Layers, back to front, in poster pixels (the poster is 1224 x 1614):

    alps    the three peaks
    mole    spire, lantern tiers, ribbed dome, colonnade and base
    city    arcaded façades with red roofs, two domes, the bell tower, the rider
    quay    the black wall, the bridge arch and the blue half-disc
    corner  the black triangle, the chequered diamond and the red triangle

The sun and the red dot are drawn in SwiftUI so they can move on their own, and so is
the river, because horizontal stripes cannot visibly drift unless they are dashed.

`layers.json` records where each layer sits in poster pixels, so the scene can put
every one back exactly where the poster had it.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from quantise import INKS, rgb, to_lab  # noqa: E402

NAMES = list(INKS)
CARTA, INCHIOSTRO, SOLE, ROSSO, BLU, SALVIA, SALVIA_SCURA, FACCIATA, NOTTE = (
    NAMES.index(n) for n in NAMES
)
PALETTE = np.array([rgb(INKS[n]) for n in NAMES], np.uint8)
CREAM = (240, 228, 194)
SCALE = 2


def clean_poster(path):
    """The poster with its lettering and its left rule painted over in stock colour."""
    image = Image.open(path).convert("RGB")
    from PIL import ImageDraw
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 566, 780), fill=CREAM)
    draw.rectangle((0, 0, 58, image.height), fill=CREAM)
    return image


def ink_map(image, box, scale=SCALE, denoise=3, radius=2):
    """Index of the nearest ink for every pixel of `box`, at `scale` times the size."""
    crop = image.crop(box)
    if denoise:
        crop = crop.filter(ImageFilter.MedianFilter(denoise))
    crop = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
    lab = to_lab(np.asarray(crop))
    lab_palette = to_lab(PALETTE)
    height = lab.shape[0]
    idx = np.empty(lab.shape[:2], np.uint8)
    for top in range(0, height, 160):  # chunked: the full distance cube would be gigabytes
        band = lab[top:top + 160]
        distance = ((band[:, :, None, :] - lab_palette[None, None, :, :]) ** 2).sum(-1)
        idx[top:top + 160] = distance.argmin(-1)
    return majority(idx, radius)


def majority(idx, radius):
    """Most common ink in each (2r+1)^2 window: removes speckle along soft edges."""
    if not radius:
        return idx
    counts = np.stack([
        ndimage.uniform_filter((idx == k).astype(np.float32), size=2 * radius + 1)
        for k in range(len(NAMES))
    ])
    return counts.argmax(0).astype(np.uint8)


def to_image(idx, alpha):
    rgba = np.zeros(idx.shape + (4,), np.uint8)
    rgba[..., :3] = PALETTE[idx]
    rgba[..., 3] = np.where(alpha, 255, 0)
    return Image.fromarray(rgba, "RGBA")


# ---------------------------------------------------------------- geometry ----
# Everything below is in poster pixels (the poster is 1224 x 1614), converted to the 2x
# working grid by `up`. The numbers were read off the ink map with a coordinate grid.

def up(value):
    return int(round(value * SCALE))


def polygon_mask(shape, points):
    from PIL import ImageDraw
    canvas = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(canvas).polygon([(up(x), up(y)) for x, y in points], fill=255)
    return np.asarray(canvas) > 0


def box_mask(shape, x0, y0, x1, y1):
    mask = np.zeros(shape, bool)
    mask[up(y0):up(y1), up(x0):up(x1)] = True
    return mask


# The cut between the Alps and the Mole's left side: the mountain's diagonal edge, then
# the cornice's slanted underside, then the colonnade's vertical edge.
MOUNTAIN_CUT = [(500, 860), (586, 960), (552, 994), (547, 997), (547, 1132), (500, 1132)]

# Where the city begins, left to right. Behind this line is the Mole's base.
CITY_LINE = [(0, 935), (520, 935), (520, 1088), (600, 1088), (600, 1115), (960, 1115), (960, 935), (1224, 935)]
RIVER_TOP = 1405          # the river's first row
RIVER_LEFT = 725          # the half-disc's vertical edge
QUAY_TOP = 1292           # the half-disc and the bridge start here
CORNER_RIGHT = 490        # the red triangle meets the half-disc here
ARCADE_BOTTOM = 1292


def city_line_mask(shape):
    """True for every pixel that is below the city line (inside the city's rows)."""
    mask = np.zeros(shape, bool)
    xs = [p[0] for p in CITY_LINE]
    ys = [p[1] for p in CITY_LINE]
    columns = np.arange(shape[1]) / SCALE
    line = np.interp(columns, xs, ys)  # y of the line at every column
    rows = (np.arange(shape[0]) / SCALE)[:, None]
    return rows >= line[None, :]


def label_touching_border(mask):
    """Connected regions of `mask` that touch the edge of the array."""
    labels, count = ndimage.label(mask)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    edge = edge[edge != 0]
    return np.isin(labels, edge)


def fit_ellipse(points_x, points_y):
    """Least-squares ellipse, possibly tilted: A x^2 + B xy + C y^2 + D x + E y = 1.

    Returns centre, the two semi-axes and the angle of the first axis in radians.
    """
    M = np.column_stack([points_x ** 2, points_x * points_y, points_y ** 2, points_x, points_y])
    A, B, C, D, E = np.linalg.lstsq(M, np.ones_like(points_x), rcond=None)[0]
    Q = np.array([[A, B / 2], [B / 2, C]])
    centre = np.linalg.solve(2 * Q, -np.array([D, E]))
    k = 1 + centre @ Q @ centre
    values, vectors = np.linalg.eigh(Q)
    radii = np.sqrt(k / values)
    angle = float(np.arctan2(vectors[1, 0], vectors[0, 0]))
    return float(centre[0]), float(centre[1]), float(radii[0]), float(radii[1]), angle


def fit_sun(idx):
    """The sun's ellipse, found by agreement with the poster's pixels.

    The poster's sun is a little taller than it is wide, and the Mole hides part of it, so
    a fit to its rim is unstable. Instead the ellipse is moved until the most pixels agree:
    inside it a pixel should be sun, outside it stock, judged only where the poster shows
    one or the other (the Mole's pixels, and the halo's, say nothing about the sun).
    """
    from scipy.optimize import minimize

    step = 4
    sun = (idx == SOLE)[::step, ::step]
    stock = (idx == CARTA)[::step, ::step]
    known = sun | stock
    ys, xs = np.mgrid[0:sun.shape[0], 0:sun.shape[1]]
    xs = xs * step / SCALE
    ys = ys * step / SCALE
    sx, sy = np.nonzero(sun)[1] * step / SCALE, np.nonzero(sun)[0] * step / SCALE

    def disagreement(p):
        cx, cy, rx, ry, angle = p
        c, s_ = np.cos(angle), np.sin(angle)
        u = (xs - cx) * c + (ys - cy) * s_
        v = -(xs - cx) * s_ + (ys - cy) * c
        inside = (u / rx) ** 2 + (v / ry) ** 2 <= 1
        return float(((inside != sun) & known).sum())

    start = [(sx.min() + sx.max()) / 2, sy.min() + (sx.max() - sx.min()) / 2,
             (sx.max() - sx.min()) / 2, (sx.max() - sx.min()) / 2, 0.0]
    best = minimize(disagreement, start, method="Nelder-Mead",
                    options={"xatol": 0.2, "fatol": 0.5, "maxiter": 2000})
    cx, cy, rx, ry, angle = best.x
    return {"cx": float(cx), "cy": float(cy), "rx": float(abs(rx)), "ry": float(abs(ry)), "angle": float(angle)}


def fit_dot(idx):
    region = np.zeros(idx.shape, bool)
    region[up(780):up(1010), up(1000):up(1224)] = True
    mask = (idx == ROSSO) & region
    ys, xs = np.nonzero(mask)
    r = np.sqrt(mask.sum() / np.pi) / SCALE
    return {"cx": xs.mean() / SCALE, "cy": ys.mean() / SCALE, "rx": r, "ry": r, "angle": 0.0}, mask


def remove_small(mask, minimum):
    """Drops connected specks smaller than `minimum` pixels."""
    labels, count = ndimage.label(mask)
    if not count:
        return mask
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    keep = np.nonzero(sizes >= minimum)[0] + 1
    return np.isin(labels, keep)


def halo(idx, centre_mask, reach):
    """Thin beige pixels hugging a disc: the antialiasing left between the sun and the sky.

    A feature is a halo when it is made of FACCIATA, lies within `reach` pixels of the
    disc, and is too thin to survive a 5 x 5 opening.
    """
    beige = idx == FACCIATA
    thin = beige & ~ndimage.binary_opening(beige, structure=np.ones((5, 5), bool))
    return thin & ndimage.binary_dilation(centre_mask, iterations=reach)


def build_masks(idx):
    """Alpha mask and ink index for every layer, on the 2x poster grid."""
    shape = idx.shape
    sun = fit_sun(idx)
    dot, dot_mask = fit_dot(idx)
    dot_mask = ndimage.binary_dilation(dot_mask, iterations=2)
    sun_mask = idx == SOLE

    background = np.isin(idx, [CARTA, SOLE]) | dot_mask
    background |= halo(idx, sun_mask | dot_mask, 6)
    below_city = city_line_mask(shape)
    cut = polygon_mask(shape, MOUNTAIN_CUT)

    # ---- mole: everything in its box that is not sky, minus the Alps' cut and the city.
    # The sky is flooded after a 3 px erosion so a one-pixel crack in an outline cannot
    # let it into the drum's cream panels; the sun seen through the lantern is cut out too.
    mole_box = box_mask(shape, 520, 30, 966, 1135)
    eroded = ndimage.binary_erosion(background | ~mole_box, iterations=3, border_value=1)
    sky = ndimage.binary_dilation(label_touching_border(eroded), iterations=3) & (background | ~mole_box)
    mole = mole_box & ~sky & ~cut & ~below_city
    mole = ndimage.binary_fill_holes(mole) & ~below_city & ~cut
    mole &= ~(sun_mask | halo(idx, sun_mask, 6))
    mole = remove_small(mole, 80)

    # ---- city: the rows below the line, left of the cut and right of the Mole, to the arcade's foot
    left_zone = box_mask(shape, 58, 935, 548, ARCADE_BOTTOM)
    right_zone = box_mask(shape, 960, 935, 1224, ARCADE_BOTTOM)
    middle_zone = box_mask(shape, 548, 935, 960, ARCADE_BOTTOM) & below_city

    # the mountain above the left roofs is "outside": flood it from the top, limited to mountain inks
    mountain_inks = np.isin(idx, [SALVIA, SALVIA_SCURA, CARTA, SOLE])
    flood_zone = box_mask(shape, 58, 770, 548, 1140)
    outside_left = label_touching_border(mountain_inks | ~flood_zone) & flood_zone
    outside_left = ndimage.binary_dilation(outside_left, iterations=2) & mountain_inks

    city = ((left_zone & ~outside_left) | (right_zone & ~background) | middle_zone) & ~mole
    city &= ~(background & ~below_city)           # sky never belongs to the city
    city &= ~cut | below_city
    city = remove_small(city, 120)
    # the façades continue below the arcade's foot, hidden behind the corner and the quay
    city |= box_mask(shape, 58, ARCADE_BOTTOM, 1224, ARCADE_BOTTOM + 140)
    city_ink = idx.copy()
    city_ink[box_mask(shape, 58, ARCADE_BOTTOM, 1224, ARCADE_BOTTOM + 140) & ~(idx == FACCIATA)] = FACCIATA

    # ---- alps: the mountain mass, with the city's silhouette painted over in mountain ink
    alps_zone = box_mask(shape, 58, 770, 590, 1140)
    alps = alps_zone & ~background & ~mole
    alps_ink = idx.copy()
    # the mountain continues under the roofs and behind the domes in its own dark ink; its real
    # pixels (including the lit facets) keep their colour, only the city's objects are painted over
    mountain_pixels = np.isin(idx, [SALVIA, SALVIA_SCURA])
    solid_rows = np.arange(shape[0])[:, None] >= up(1100)
    under_roofs = box_mask(shape, 58, 935, 548, 1140) & solid_rows
    objects = city & box_mask(shape, 58, 935, 548, 1100)
    alps |= under_roofs | objects
    alps_ink[(under_roofs | objects) & ~mountain_pixels] = SALVIA_SCURA
    alps &= ~(box_mask(shape, 548, 770, 590, 1140) & ~cut)
    alps = ndimage.binary_fill_holes(alps)
    alps = remove_small(alps, 200)
    # behind the Mole's left side: more mountain, so a shift never shows the sky through
    extension = box_mask(shape, 548, 995, 660, 1140)
    alps |= extension
    alps_ink[extension & (~alps_ink.astype(bool) | True) & ~(alps & (idx != CARTA) & ~extension)] = SALVIA_SCURA
    alps_ink[ndimage.binary_fill_holes(alps) & (alps_ink == CARTA)] = SALVIA_SCURA

    # ---- the mole continues down behind the city
    mole_ink = idx.copy()
    behind = box_mask(shape, 548, 1085, 960, 1150)   # a hand's breadth: only the tilt can open a gap here
    fill = behind & ~mole
    fill &= (np.arange(shape[0])[:, None] >= up(MOLE_FILL_TOP))
    mole |= fill
    mole_ink[fill] = FACCIATA

    # ---- corner and quay are plain polygons: nothing in them is sky
    corner = box_mask(shape, 58, ARCADE_BOTTOM, CORNER_RIGHT, 1614)
    corner |= polygon_mask(shape, [(58, 1195), (300, 1310), (300, ARCADE_BOTTOM), (58, ARCADE_BOTTOM)])
    black_triangle = polygon_mask(shape, [(58, 1195), (300, 1310), (58, 1310)])
    corner &= ~(box_mask(shape, 58, 1195, 300, ARCADE_BOTTOM) & ~black_triangle)
    corner |= black_triangle
    corner |= box_mask(shape, 58, ARCADE_BOTTOM, CORNER_RIGHT, 1614)
    quay = box_mask(shape, CORNER_RIGHT, QUAY_TOP, 1224, 1614)
    quay &= ~box_mask(shape, RIVER_LEFT, RIVER_TOP, 1224, 1614)
    # The poster's own right margin leaves a block of bare stock on top of the bridge; it is stone.
    quay_ink = idx.copy()
    bridge = box_mask(shape, 900, QUAY_TOP, 1224, RIVER_TOP)
    quay_ink[bridge & (idx == CARTA)] = FACCIATA

    return {"mole": mole, "mole_ink": mole_ink, "city": city, "city_ink": city_ink, "alps": alps,
            "alps_ink": alps_ink, "corner": corner, "quay": quay, "quay_ink": quay_ink, "sun": sun, "dot": dot,
            "background": background}


# ----------------------------------------------------------------- compose ----

LAYERS = ["alps", "mole", "city", "corner", "quay"]   # back to front, with the sun behind alps
                                                      # and the dot between mole and city


def compose(masks, idx):
    """Every layer stacked at zero offset on the stock, the way the app draws them."""
    from PIL import ImageDraw
    shape = idx.shape
    out = np.full(shape, CARTA, np.uint8)
    sun, dot = masks["sun"], masks["dot"]

    def disc(spec, ink):
        canvas = Image.new("L", (shape[1], shape[0]), 0)
        t = np.linspace(0, 2 * np.pi, 720)
        ex, ey = spec["rx"] * np.cos(t), spec["ry"] * np.sin(t)
        c, s_ = np.cos(spec["angle"]), np.sin(spec["angle"])
        points = [(up(spec["cx"] + c * x - s_ * y), up(spec["cy"] + s_ * x + c * y)) for x, y in zip(ex, ey)]
        ImageDraw.Draw(canvas).polygon(points, fill=255)
        out[np.asarray(canvas) > 0] = ink

    disc(sun, SOLE)
    for name in LAYERS:
        ink = masks.get(name + "_ink", idx)
        alpha = masks[name]
        out[alpha] = ink[alpha]
        if name == "mole":
            disc(dot, ROSSO)
    # the river is drawn in SwiftUI; for the comparison it is taken from the poster as it is
    river = box_mask(shape, RIVER_LEFT, RIVER_TOP, 1224, 1614)
    out[river] = idx[river]
    return out


def difference(composite, idx):
    """Share of pixels, inside the poster's own artwork, that the layers get wrong."""
    shape = idx.shape
    area = box_mask(shape, 58, 0, 1224, 1614) & ~box_mask(shape, 58, 0, 566, 780)
    return float((composite[area] != idx[area]).mean())


# ------------------------------------------------------------------ export ----

# The scene is the poster without its empty left margin and the empty sky above the spire.
ORIGIN = (58, 30)
SIDE_PAD = 192            # 128 for a screen wider than the poster, 64 more for the tilt to slide into
MOLE_FILL_TOP = 1100          # below this the Mole's layer is only filler, hidden by the city
SCENE = (1224 - 58, 1614 - 30)


def river_spec(idx):
    """Where the river's cream stripes sit, measured from the poster."""
    top, left = up(RIVER_TOP), up(RIVER_LEFT + 40)
    band = idx[top:, left:up(1200)]
    cream = (band == CARTA).mean(axis=1)
    rows = np.nonzero(cream > 0.6)[0]
    stripes, start = [], None
    for index, row in enumerate(rows):
        if start is None:
            start = previous = row
        elif row != previous + 1:
            stripes.append((start, previous)); start = row
        previous = row
    if start is not None:
        stripes.append((start, previous))
    return {
        "x": RIVER_LEFT - ORIGIN[0], "y": RIVER_TOP - ORIGIN[1],
        "w": 1224 - RIVER_LEFT, "h": 1614 - RIVER_TOP,
        "stripes": [{"y": (RIVER_TOP + a / SCALE) - RIVER_TOP, "h": (b - a + 1) / SCALE} for a, b in stripes],
    }


def export(masks, idx, out):
    os.makedirs(out, exist_ok=True)
    layers = {}
    for name in LAYERS:
        alpha = masks[name]
        ink = masks.get(name + "_ink", idx)
        ys, xs = np.nonzero(alpha)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        crop_ink, crop_alpha = ink[y0:y1, x0:x1], alpha[y0:y1, x0:x1]
        # A layer that touches the edge of the scene is extended sideways by repeating its edge
        # column, so a tilt that slides it never uncovers the stock behind.
        left_pad = SIDE_PAD * SCALE if x0 <= up(ORIGIN[0]) + 2 else 0
        right_pad = SIDE_PAD * SCALE if x1 >= up(1224) - 2 else 0
        if left_pad or right_pad:
            # Repeat a column a little inside the artwork, not the edge itself: the poster's own
            # left margin was painted out to stock colour, and the filters leave the first few
            # columns blended with it.
            inner = 8
            crop_ink = crop_ink.copy()
            crop_alpha = crop_alpha.copy()
            if left_pad:
                crop_ink[:, :inner] = crop_ink[:, inner:inner + 1]
                crop_alpha[:, :inner] = crop_alpha[:, inner:inner + 1]
            if right_pad:
                crop_ink[:, -inner:] = crop_ink[:, -inner - 1:-inner]
                crop_alpha[:, -inner:] = crop_alpha[:, -inner - 1:-inner]
            if name == "city":
                # The arcades continue as their own mirror image, not as a smear of one column.
                left_ink = crop_ink[:, inner + 1:inner + 1 + left_pad][:, ::-1]
                left_alpha = crop_alpha[:, inner + 1:inner + 1 + left_pad][:, ::-1]
                right_ink = crop_ink[:, -1 - right_pad:-1][:, ::-1]
                right_alpha = crop_alpha[:, -1 - right_pad:-1][:, ::-1]
            else:
                left_ink = np.repeat(crop_ink[:, inner:inner + 1], left_pad, axis=1)
                left_alpha = np.repeat(crop_alpha[:, inner:inner + 1], left_pad, axis=1)
                right_ink = np.repeat(crop_ink[:, -1:], right_pad, axis=1)
                right_alpha = np.repeat(crop_alpha[:, -1:], right_pad, axis=1)
            crop_ink = np.concatenate([left_ink, crop_ink, right_ink], axis=1)
            crop_alpha = np.concatenate([left_alpha, crop_alpha, right_alpha], axis=1)
            x0, x1 = x0 - left_pad, x1 + right_pad
        image = to_image(crop_ink, crop_alpha)
        path = os.path.join(out, f"scene-{name}.png")
        image.save(path, optimize=True)
        layers[name] = {
            "file": f"scene-{name}",
            "x": x0 / SCALE - ORIGIN[0], "y": y0 / SCALE - ORIGIN[1],
            "w": (x1 - x0) / SCALE, "h": (y1 - y0) / SCALE,
            "bytes": os.path.getsize(path),
        }
    def shape(spec, ink):
        return {"cx": spec["cx"] - ORIGIN[0], "cy": spec["cy"] - ORIGIN[1], "rx": spec["rx"], "ry": spec["ry"],
                "angle": spec["angle"], "ink": ink}
    manifest = {
        "scene": {"w": SCENE[0], "h": SCENE[1]},
        "order": ["sun", "alps", "mole", "dot", "city", "corner", "quay", "river"],
        "layers": layers,
        "sun": shape(masks["sun"], "sole"),
        "dot": shape(masks["dot"], "rosso"),
        "river": river_spec(idx),
    }
    with open(os.path.join(out, "layers.json"), "w") as handle:
        json.dump(manifest, handle, indent=2)
    return manifest


def swift_geometry(manifest):
    """The manifest as Swift constants, so the scene is placed by numbers nobody retyped."""
    def num(value):
        return f"{value:.2f}".rstrip("0").rstrip(".") if "." in f"{value:.2f}" else f"{value}"
    lines = [
        "// Generated by tools/art/poster_layers.py from the reference poster. Do not edit by hand.",
        "import CoreGraphics",
        "",
        "/// Where each depth layer of the poster scene sits, in poster pixels measured from the",
        "/// scene's top-left corner. Layers are drawn back to front in the order listed.",
        "enum PosterSceneGeometry {",
        f"    static let size = CGSize(width: {num(manifest['scene']['w'])}, height: {num(manifest['scene']['h'])})",
        "",
        "    struct Placement: Sendable {",
        "        let image: String",
        "        let frame: CGRect",
        "    }",
        "",
    ]
    for name, spec in manifest["layers"].items():
        lines.append(
            f"    static let {name} = Placement(image: \"{spec['file']}\", frame: CGRect("
            f"x: {num(spec['x'])}, y: {num(spec['y'])}, width: {num(spec['w'])}, height: {num(spec['h'])}))")
    lines += [
        "",
        "    /// Where the Mole's own artwork ends. Below it the layer holds only filler that the city hides;",
        "    /// a screen that shows the Mole alone clips the scene here.",
        f"    static let moleBase: CGFloat = {MOLE_FILL_TOP - ORIGIN[1]}",
    ]
    lines += ["", "    struct Disc: Sendable {", "        let centre: CGPoint", "        let radii: CGSize", "        let angle: Double", "    }", ""]
    for key in ("sun", "dot"):
        d = manifest[key]
        lines.append(
            f"    static let {key} = Disc(centre: CGPoint(x: {num(d['cx'])}, y: {num(d['cy'])}), "
            f"radii: CGSize(width: {num(d['rx'])}, height: {num(d['ry'])}), angle: {d['angle']:.5f})")
    r = manifest["river"]
    lines += [
        "",
        f"    static let river = CGRect(x: {num(r['x'])}, y: {num(r['y'])}, width: {num(r['w'])}, height: {num(r['h'])})",
        "    /// The cream stripes, as (offset from the river's top, thickness).",
        "    static let riverStripes: [(y: CGFloat, height: CGFloat)] = [",
    ]
    for stripe in r["stripes"]:
        lines.append(f"        ({num(stripe['y'])}, {num(stripe['h'])}),")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("poster")
    parser.add_argument("out")
    parser.add_argument("--swift", help="also write the geometry as a Swift file")
    args = parser.parse_args()

    image = clean_poster(args.poster)
    idx = ink_map(image, (0, 0, image.width, image.height))
    masks = build_masks(idx)
    composite = compose(masks, idx)
    manifest = export(masks, idx, args.out)
    to_image(composite, np.ones(composite.shape, bool)).convert("RGB").save(
        os.path.join(args.out, "_composite.png"))
    print(f"composite differs from the poster by {difference(composite, idx) * 100:.3f}%")
    for name, spec in manifest["layers"].items():
        print(f"  {name:7s} {spec['w']:.0f} x {spec['h']:.0f} at ({spec['x']:.0f}, {spec['y']:.0f}), {spec['bytes'] // 1024} KB")
    print("  river stripes:", [(round(float(t["y"]), 1), float(t["h"])) for t in manifest["river"]["stripes"]])
    if args.swift:
        with open(args.swift, "w") as handle:
            handle.write(swift_geometry(manifest))
        print("  wrote", args.swift)


if __name__ == "__main__":
    main()
