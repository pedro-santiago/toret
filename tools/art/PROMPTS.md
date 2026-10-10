# How the artwork was made

The poster-style illustrations in `Toret/Resources/Assets.xcassets` (`art-*`) were drawn
with a local image model, then printed onto the app's nine inks so they look screen-printed
rather than generated. Nothing here uses the reference poster as an input image: the model
was only given a written description of the *style* (flat vector gouache, limited palette,
hard edges, geometric shapes) and a different subject, Turin's fountains.

## Model and licence

| | |
| --- | --- |
| Model | FLUX.2 [klein] 4B, 4-bit MLX conversion `mlx-community/flux2-klein-4b-4bit` |
| Snapshot | `860e87183ceb29e39627c0612ebd66d8ea66e68c` |
| Licence | Apache License 2.0 — checked on the Hugging Face cards of both `mlx-community/flux2-klein-4b-4bit` and `black-forest-labs/FLUX.2-klein-4B` ("Open weights available for commercial use under the Apache 2.0 license"), 2026-10-10 |
| Runner | `mflux` 0.20.0 (`mflux-generate-flux2`), Apple M4 Pro, 4 steps, default guidance |

## Prompts and seeds

`tools/art/generate.sh` is the source of truth for the prompts (`STYLE`, `TORET`, `SKYLINE`,
`ICON`). The picks:

| Asset | Job and seed | Size generated |
| --- | --- | --- |
| `art-toret` | `generate.sh toret-portrait 41` | 768 × 1024 |
| `art-toret-wide` | `generate.sh toret-wide 71` | 1152 × 768 |
| `art-skyline-tall` | `generate.sh skyline-tall 61` | 576 × 1248 |
| `art-skyline-wide` | `generate.sh skyline-wide 82` | 1152 × 640 |
| `icon-candidates/icon-a…c` | `generate.sh icon 52`, `53`, `51` | 1024 × 1024 |
| `icon-candidates/icon-d` | hand-drawn SVG, `icon_vector.py` | 1024 × 1024 |

Other seeds were generated and rejected: wobbly geometry, two suns, lost water stream,
muddy colour.

## Printing onto the inks

`tools/art/quantise.py` crops the border the model leaves, upscales, removes noise, moves
every pixel to the nearest of the nine inks in CIELAB, and removes islands a printer would
never leave. The exact commands:

```sh
uv run --with pillow --with numpy tools/art/quantise.py raw/toret-portrait_41.png art-toret.png \
  --crop 28,28,740,1002 --scale 2 --mode 3 --denoise 5 --min-area 900 \
  --fix "carta>facciata@0,1300,1424,1600" --fix "salvia,notte,salviaScura>inchiostro@0,1170,250,1312" \
  --fix "inchiostro,notte>salviaScura@1322,1190,1424,1312"

uv run --with pillow --with numpy tools/art/quantise.py raw/toret-wide_71.png art-toret-wide.png \
  --crop 28,32,1126,746 --scale 1.8 --mode 3 --denoise 5 --min-area 900 --hue "178-222:0.35>blu" \
  --fix "inchiostro>salviaScura@636,892,712,952" --fix "blu>inchiostro@780,750,880,880"

uv run --with pillow --with numpy tools/art/quantise.py raw/skyline-tall_61.png art-skyline-tall.png \
  --crop 41,45,535,1199 --scale 1.75 --mode 3 --denoise 3 --min-area 500 --hue "100-142:0.45>inchiostro"

uv run --with pillow --with numpy tools/art/quantise.py raw/skyline-wide_82.png sw_q.png \
  --crop 14,16,1138,622 --scale 1.8 --mode 2 --denoise 3 --min-area 250 --hue "100-142:0.45>inchiostro"
uv run --with pillow --with numpy tools/art/repaint_sun.py sw_q.png art-skyline-wide.png \
  --sun 1447,352,309 --dot 250,170,62 --sky-below 640
```

`--hue` repaints a hue band as an ink before quantising (the saturated green of the dome and
spire, and the cyan of the water, are not in the palette). `--fix` is an explicit retouch of a
rectangle after quantising. `repaint_sun.py` replaces the model's lopsided sun with an exact
disc and adds the poster's separate red dot.

## Not generated

- `docs/images/architecture.svg`, `data-flow.svg`, `banner.svg/png` — drawn by
  `tools/art/diagrams.py`; every letter is an outline from the bundled League Spartan and Archivo.
- `paper-grain` — procedural noise, `tools/art/paper_grain.py`.
- `tools/art/icon-candidates/icon-d` — drawn by hand in `tools/art/icon_vector.py`.

The model cannot set type, so the artwork has no text; titles are always set in SwiftUI.
