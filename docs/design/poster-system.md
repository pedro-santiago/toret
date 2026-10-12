# Toret poster system

Toret is printed, not rendered. Every screen is one plate of a mid-century Turin
travel poster: flat ink on cream stock, a giant black title, and a few geometric
shapes doing real work. There is no glass, no blur, no gradient and no shadow
anywhere in the app. If a thing needs emphasis it gets bigger, blacker or a
different one of the three inks. It does not get softer.

This is the contract for everyone drawing UI. Tokens live in
`Shared/DesignSystem/` (`Palette.swift`, `Typography.swift`, `Poster.swift`,
`Glass.swift`). Nothing hard-codes a colour or a font.

## Inks

| Token | Hex | Used for |
| --- | --- | --- |
| `carta` | `#F0E3BF` | The stock. Every daytime screen. |
| `cartaScura` | `#E3D3A5` | Stock in shadow: a second panel tone. |
| `cartaChiara` | `#F7EDD0` | A plate laid on the stock. |
| `inchiostro` | `#16130F` | Type, rules, frames, the needle. Never `#000`. |
| `sole` | `#E9B33B` | The sun. Weak flow. **Fill only, never text** (no contrast on cream). |
| `rosso` | `#B7301F` | The red dot. Dry. Warnings. Destructive actions. |
| `blu` | `#2C61A0` | The river. Running water. The interactive colour (links, selection). |
| `salvia` / `salviaScura` | `#8CA48F` / `#5C7864` | The Alps. Decoration only. |
| `facciata` | `#D9C79A` | Ochre façades. Decoration only. |
| `notte` | `#12161C` | The night plate: the compass screen, lock screen. |
| `luna` | `#F1D98A` | The sun at night. |

Text is `inchiostro` on `carta` (15:1) or `carta` on `inchiostro`/`notte`.
`blu` and `rosso` reach 4.5:1 on `carta` and may be used for text; `sole` may not.
Captions use `inchiostro` at 0.7 or more, never less.

## Water state is a shape, not a colour

Colour is never the only channel. `StateMark` draws all four:

| State | Shape | Ink |
| --- | --- | --- |
| Running (`corrente`) | circle | `blu` |
| Weak (`debole`) | half-disc | `sole`, black outline |
| Dry (`secca`) | triangle | `rosso` |
| Nobody has reported (`ignota`) | empty ring | `inchiostro` 55% |

Most pins are "nobody has reported", and an empty ring must look calm and
intentional, not broken. The selected pin grows; it does not change colour.

## Type

- **League Spartan Black** (`Typo.display`) is the poster: titles, figures,
  anything that answers a question. Tight leading (0.8), tracking −1%. Never
  lighter than Bold.
- **Archivo** (`Typo.ui`) is everything you read: rows, captions, buttons, body.
  `Typo.narrow` for small labels.
- Titles are **uppercase, broken over two lines** like TU / RIN and filled to the
  width of the plate: `PosterTitle("PER", "TO")`. The black vertical rule down their
  left edge is part of the title.
- Sentence case everywhere else. No tracked all-caps eyebrows, no
  `A · B · C` meta strings as chrome, no `→` on buttons. The poster's own
  uppercase is for the display words only.
- Scale: title 84–96, figure 56–120, headline 22–28, body 16, caption 13. Display
  type scales with Dynamic Type up to about 1.35×; body scales fully.

## Shapes

Circles, half-discs, triangles, diamonds, rectangles. **No rounded rectangles,
no pills.** Square corners; the only curves are true circles and arches.
Heavy rules are 3 pt, row rules 1.5 pt, plate frames 2.5 pt, all `inchiostro`.

Large decoration is the same vocabulary grown up: `SunDisc`, `WaterStripes`
(the river; drifts sideways when the water is running), `DiamondChecker`,
`MountainRange`, `ArcadeStrip`, `MoleSilhouette`. One of them per screen is a
hero; the rest stay quiet.

## Components

- **Plate** (`.plate()` / legacy `glassPane`): opaque `carta` or `cartaChiara`,
  2.5 pt black frame, square. Replaces every card and every pane.
- **Row**: state mark (24) · name (Archivo 700/18) + one plain line under it
  (Archivo 14, 0.7) · distance (Spartan 800/30) + "m" (Archivo 14). 1.5 pt rule
  between rows. No chevrons.
- **Primary button**: full-width `inchiostro` rectangle, 56 pt, `carta` Spartan
  800/20 label, a yellow circle at the trailing edge. Attention actions use
  `rosso`. **Secondary**: 2.5 pt black frame, no fill.
- **Chip / filter**: 2 pt black frame rectangle, 36 pt tall; on = filled
  `inchiostro` with `carta` text.
- **Tab bar**: flat `carta`, 3 pt black rule on top. Each tab is a drawn shape
  with a label. The sun (`sole` disc) sits behind the selected tab's glyph and
  slides between tabs with a spring.
- **Status**: a `StateMark` and one sentence. "Sem relato recente", "Água corrente,
  relato há 2 h".

## Screens

- **Mapa**: MapKit washed to cream, water in `blu`. Pins are `StateMark`s. A
  bottom plate carries the selected fountain: name in Spartan 800/28, distance
  as the big figure, a black "Traçar rota" button.
- **Perto**: `PosterTitle("PER","TO")`, one line saying where distances are
  measured from, then rows. The sun disc sits half off-screen behind the title.
- **Salvas**: `PosterTitle("SAL","VAS")`. Empty state is a diamond and one sentence.
- **Relatos**: `PosterTitle("RELA","TOS")`. Feed rows with stars drawn as
  diamonds.
- **Ajustes**: `PosterTitle("AJUS","TES")`. Plain grouped rows, heavy rule between
  groups.
- **Fonte**: a full-bleed fountain plate (see Fountain plates below), the name in
  Spartan 900/44, three heavy figures (distance, minutes, rating) split by
  3 pt vertical rules, community section, specs.
- **Bússola** (night): the moon disc (`luna`) is the dial. The distance sits in
  it in `inchiostro` at 120 pt. The needle is a black triangle; the dial turns with
  the phone. Landmarks are flat marks on the rim (the Mole is the real
  silhouette); the rest are shapes: dome, square, arch, peaks.
- **Rota**: the instruction is the poster: the number of metres at 120 pt, one
  line of Archivo under it.

## Fountain plates

Every fountain has its own small poster, `FountainPlate` (`Shared/DesignSystem/FountainPlate.swift`,
layout in `FountainPlateSpec.swift`). It is the hero of **Fonte** and the thumbnail on
each **Perto** row. Nothing is stored per fountain: the picture is composed in code from
three facts, and the same fountain always gets the same one.

- **Kind** picks the subject: one of 3 to 4 printed plates of a toret, a basin
  fountain, a bubbler or a refill post (`plate-<kind>-<a…>` in the asset catalogue, made
  by the local model, see `tools/art/PROMPTS.md`). A stable hash may also mirror it.
- **Neighbourhood** (35 named, some fountains with none) picks the backdrop, one landmark from the skyline
  kit or a flat motif (chequered diamond, three bands), and with the hash one of five ink
  pairings (`daylight`, `gold`, `river`, `ochre`, `brick`). A fountain with no known
  neighbourhood gets only the geometry.
- **The OSM node id**, through a fixed FNV-1a and SplitMix64 stream (never Swift's seeded
  `Hasher`), drives the sun's position and size, the red dot's position, the number of
  ground stripes (2 to 4), the backdrop's place and the subject variant, so neighbours
  differ.

Printed like the rest: flat, no gradient, a heavy rule on the ground line, a 4 px keyline
on the subject. At night (`night: true`) the sky is `notte`, the sun becomes the `luna`
disc and moves behind the subject so a black head always stands on light.

**The honesty rule.** The plate never implies the state of the water. There is no stream
from the spout, no puddle, no running or dry art, no liquid in a basin, no blue in a
subject, and the spec is built from id, kind and neighbourhood alone (a test builds it
from fountains in every water state and requires the same result). The blue stripes on
the ground are decoration and appear on every plate whatever the state. Water state is
shown by `StateMark` and the community sentence, which sit next to the plate, never in it.
The plate is decorative and hidden from VoiceOver.

## Motion

Printed things do not glow; they slide, snap and stack.

- The sun slides between tabs. Pins pop in with a short overshoot spring.
  The needle swings on a spring and settles. Distances count up (`CountingMetres`).
- When the water is running, `WaterStripes` drifts. Nothing else loops.
- One orchestrated moment: on launch the sun rises from the horizon into place
  and the title wipes in line by line. Once per cold start.
- Rows enter with a 12 pt rise and a 30 ms stagger the first time a list appears,
  never on scroll.
- Every animation is interruptible and honours Reduce Motion (crossfade or cut).

## Copy

Plain pt-BR for now (en/it to follow), sentence case, active voice, one job per
line. Say what the data is: "Posição do OpenStreetMap", "Sem relato recente".
Never claim water is running unless a dated community report says so.
