# Accessibility

What the app does, what it measured, and what is missing. Everything here comes from
reading the code and from a script (below). **Nothing has been tested with VoiceOver,
Voice Control, Switch Control or at accessibility text sizes on a real device.** Treat
the claims as "implemented", not "verified".

## VoiceOver

Counts across `Toret/`, `Shared/`, `ToretWidgets/` (grep): about 36 `accessibilityLabel`,
6 `accessibilityHint`, 8 `accessibilityValue`, 38 `accessibilityElement`, 16
`accessibilityAddTraits`, 43 `accessibilityHidden`, 1 `accessibilityAdjustableAction`.

| Element | What VoiceOver gets | Source |
| --- | --- | --- |
| Tab bar | Each tab is a button labelled with its title; the selected one has the selected trait | `ToretTabBar.swift` |
| Poster titles | One element with the lines joined ("Perto") and the header trait | `Poster.swift`, `Typography.swift` |
| Map pin | Label "place, plate title"; value "state label, a 84 metros"; hint opens detail | `MapFurniture.swift` |
| Pin cluster | "N fontes", hint "Aproxima o mapa" | `MapFurniture.swift` |
| User position, landmarks | "Você está aqui"; landmark names | `MapScreen.swift`, `MapFurniture.swift` |
| Filter chip | Label = filter title, value = match count, selected trait | `Chrome.swift` |
| Fountain row | Label "title, kind", value (distance and state), hint "Abre a página da fonte" | `FountainRow.swift` |
| State mark | The state label (or its sentence) | `FountainRow.swift` / `Poster.swift` |
| Map legend | One element: "círculo, água corrente; meio disco, fluxo fraco; triângulo, sem água; anel vazio, sem relato recente" | `Chrome.swift` |
| Compass | Label "Bússola. <place>", value = the spoken direction; **an announcement "Alinhado com a fonte"** when the needle lines up | `CompassScreen.swift` |
| Counting distance | "N metros" (not the animated intermediate numbers) | `CountingNumber.swift` |
| Rating | Read-only: "Nota 4,6 de 5". Input: "Sua nota", value "3 de 5", **adjustable** (swipe up/down) | `CommunityComponents.swift` |
| Switches | Value "Ligado"/"Desligado" | `Chrome.swift` |
| External links | Hint "Abre no navegador" | `SettingsScreen.swift` |
| Weather line | Spoken form with the source: "...Fonte: Open-Meteo, 14:05." | `ConditionsViews.swift` |
| Widgets | One full sentence per tile/row: "place, 84 metros para NO, 2 minutos a pé" (plus state when known) | `WidgetProvider`/`WidgetReading.swift`, `FountainWidgetViews.swift` |
| Live Activity | A spoken summary on the disc | `WalkViews.swift` |
| Decoration | Fountain plates, illustrations, skyline, parallax, water stripes, launch overlay: hidden | `accessibilityHidden` |

**Gaps**

- No custom actions and no rotors. On Salvas, the route and the remove action exist only
  in a long-press context menu; nothing announces it to VoiceOver users.
- No `accessibilityIdentifier`s and no UI tests; accessibility is not covered by the
  automated suite.
- The map can hold up to 220 annotations (`ToretModel.mapPins`); the VoiceOver
  reading order over many pins has not been checked.
- Heading structure inside Detail is partial (only some section titles carry the header
  trait), and no reading-order tuning (`accessibilitySortPriority`) is done.

## Dynamic Type

Fonts are built from point sizes through `UIFontMetrics` (`Shared/DesignSystem/Typography.swift`,
`TypeScale`) and redraw when the system size changes.

| Role | Scales | Used for |
| --- | --- | --- |
| `text` | fully, like `.body` | reading text, buttons (Archivo above 13.5 pt) |
| `label` | like `.footnote`, capped at 2.2x | small labels, captions (Archivo up to 13.5 pt, narrow cut) |
| `display` | like `.largeTitle`, **capped at 1.35x** | League Spartan titles and figures |

- Rows and a few headers switch to a stacked layout at accessibility sizes
  (`FountainRow`, `Chrome.swift` 237) and the compass dial shrinks to 0.78
  (`CompassScreen`). The 56 and 120 pt figures use `@ScaledMetric`
  (`MapScreen`, `RouteScreen`).
- Titles shrink to fit with `minimumScaleFactor` (24 uses), so a long Italian word does
  not clip.
- The **widget extension is opted out** of `TypeScale`: layout is fixed per family and
  the system scales widget text where it should.
- **Gap:** display type stops at 1.35x by design (a 120 pt figure that doubled would leave
  its disc), so at the largest accessibility sizes the poster figures are smaller than
  the text around them. Not reviewed screen by screen at AX5.

## Reduce Motion

`Shared/DesignSystem/Motion.swift` reads `UIAccessibility.isReduceMotionEnabled`; every
curve and spring becomes a 0.16 s ease-out (counting is skipped; stagger is zero).
Views also read `\.accessibilityReduceMotion` directly: tab bar, map, route, detail,
launch overlay (skipped), parallax, illustration, empty scenes (no bob or march),
transitions. The tilt parallax is off under Reduce Motion and Low Power Mode. No
animation conveys state that is not also in text or shape.

## Colour and contrast

The app has one palette; it forces the light scheme (`.preferredColorScheme(.light)`)
and the compass forces dark. Ratios below are WCAG 2.x relative-luminance contrast of the
real tokens in `Shared/DesignSystem/Palette.swift`, computed by a script (opacities
blended over the stated background).

| Pair | Ratio | Meets |
| --- | --- | --- |
| inchiostro on carta (body, titles) | 14.50 | AAA |
| inchiostro on cartaChiara | 15.85 | AAA |
| inchiostro on cartaScura | 12.46 | AAA |
| carta on inchiostro (primary button) | 14.50 | AAA |
| carta on notte (compass text) | 14.21 | AAA |
| inchiostro on luna (compass figure) | 13.25 | AAA |
| luna on notte | 12.99 | AAA |
| blu on carta / on cartaChiara | 4.95 / 5.41 | AA text |
| rosso on carta / on cartaChiara | 4.76 / 5.20 | AA text |
| carta on rosso (alert button) | 4.76 | AA text |
| correnteNotte on notte | 6.82 | AA text |
| seccaNotte on notte | 5.79 | AA text |
| sole on notte | 9.48 | AAA |
| inchiostro on sole | 9.68 | AAA |
| inchiostro at 0.78 / 0.75 / 0.72 / 0.70 on carta (captions) | 7.95 / 7.24 / 6.57 / 6.17 | AAA / AAA / AA+ / AA+ |
| inchiostro at 0.55 on carta (the "no report" ring) | 3.80 | non-text 3:1 |
| inchiostro at 0.62 on carta (search placeholder) | 4.74 | AA text |
| inchiostro at 0.60 on carta / cartaChiara (review note placeholder) | 4.47 / 4.60 | **just below AA on carta**; which ground the field uses was not checked |
| **sole on carta** | **1.50** | fails: used as a fill only, never text |
| salvia / salviaScura / facciata on carta | 2.10 / 3.80 / 1.31 | decoration only |

The script is a short WCAG formula; reproduce it with any contrast tool using the hex
values in [../design/poster-system.md](../design/poster-system.md). That document says
the cream/black pair is "15:1"; the computed value is 14.50:1.

**Colour-independence of water state.** The four states differ by *shape* (circle,
half-disc, triangle, empty ring) and by a text label, in every place that shows a state
(pin, row, detail sentence). The yellow half-disc has a black outline, so its
non-text contrast comes from the ink (14.50), not from the 1.50 yellow. The map legend
and its spoken form list all four.

**Gaps:** no handling of Increase Contrast or Differentiate Without Color
(no code reads those settings; the design does not rely on colour so the latter is
largely moot). No dark mode for the main app by design. Smart Invert is not handled.

## Hit targets

| Control | Size | Notes |
| --- | --- | --- |
| Tab bar buttons | 64 pt tall, 1/5 width | `ToretTabBar.contentHeight` |
| Primary / secondary buttons | 52-56 pt tall, full width (the secondary button in permission messages is 44) | `Chrome.swift`, `EmptyScene.swift` |
| Rows | at least 44 pt | `FountainRow` |
| Filter chips | 36 pt visible + 4 pt padding each side = 44 | `Chrome.swift` |
| Map controls (locate, compass) | 56 pt (48 inner) | `MapFurniture.swift` |
| Back / save on detail, compass back | 46 pt | `DetailScreen`, `CompassScreen` |
| Search clear, report "mais opções", link rows | 44 pt | `Chrome.swift`, `ReportRow.swift`, `SettingsScreen.swift` |
| **Tag chips** (review sheet) | **36 pt**, no extra padding | `TagChip` in `CommunityComponents.swift` |
| **Diamond rating input** | **36 pt**, 10 pt apart | `DiamondRatingInput` |
| Map pins | small marks; the hit area is larger (`contentShape`) but not measured | `MapFurniture.swift` |

## Haptics

All through SwiftUI `sensoryFeedback` or the `.haptic` modifier (`Shared/DesignSystem/Haptics.swift`),
so they follow the system setting: tab and chip selection (selection), saving a fountain
(success / rigid impact), the review sheet (success on send, error on rejection, warning
on a fourth tag attempt), compass (rigid tick when aligned, heavy "arrival" under 20 m,
selection when the fountain changes), the walk route (success on arrival), the rating
(selection), light impacts when the Perto list reveals more. `Haptics.fire(_:)` (the
UIKit variant) is defined but not used.

## Other

- **Voice and Siri** give the same answer as the widget as a spoken sentence
  (`Shared/Model/SpokenAnswer.swift`).
- **Alternative to the compass:** the plate under the dial states the direction in words
  and the list of nearest fountains is readable without it.
- **Language:** the app is in three languages; VoiceOver speaks in the device language.
  The handle "Visitante 4F2A91" is Portuguese in all of them
  ([localization-ux.md](localization-ux.md)).
- **Orientation:** portrait only.

## Priorities if this is revisited

1. Pad the tag chips and rating diamonds to 44 pt.
2. Make the review note placeholder 0.7 or darker.
3. Test with VoiceOver on a device, including the map, the compass announcement and the
   widget sentences.
4. Walk every screen at the largest Dynamic Type size.
5. Add custom accessibility actions (save, route) to list rows.
