# UX principles

The principles below are the ones the code actually embodies. Each names where to
see it. The visual language that carries them is specified in
[../design/poster-system.md](../design/poster-system.md); this page does not repeat it.

## 1. Honesty first

*The app says only what it can back up, and says where it comes from.*

- A fountain is **"Sem relato recente"** until someone reports otherwise; the default
  mark is an empty ring that must look calm, not broken. A report is believed for
  36 hours (`Shared/Model/Report.swift`, `CommunitySummary.freshness`).
- Every state carries its **provenance**: "Relato há 2 h", "Último relato há 3 dias"
  (`CommunitySummary.provenance`).
- Distances are never silently measured from somewhere else. When the app measures
  from Piazza San Carlo (permission off, no fix yet, outside Turin) a visible sentence
  says so, the same one on the map and the compass
  (`LocationStatus.explanation` in `Toret/State/LocationProvider.swift`).
- Weather is context only, with source and time: "Turim agora: 24 °C, sensação 25 °C ·
  Open-Meteo, 14:05" (`Toret/Conditions/ConditionsViews.swift`).
- The fountain plate (the little poster of each fountain) **never draws water**, so
  the picture cannot disagree with the state next to it
  (poster-system.md, "The honesty rule").
- The proximity notification does not say the water runs: "Ela não diz se a água está
  correndo" is printed beside the switch in Ajustes.

Full table of claims: [data-and-honesty.md](data-and-honesty.md).

## 2. Glanceability

*The answer is one big number, readable while walking.*

- The distance is the poster figure: 120 pt on the compass and the walk route, a
  large figure on the map plate and in each Perto row, Spartan Black, scaled with
  Dynamic Type up to 1.35x (`Shared/DesignSystem/Typography.swift`).
- Direction is spoken as something to *look at*, not a number of degrees: "Olhe entre
  a Mole Antonelliana e a Basilica di Superga" (en: "Look between the Mole Antonelliana
  and the Basilica of Superga"; `Landmark.orientation`, `Shared/Model/Landmark.swift`).
  The shorter "olhe entre a Mole e Superga" in the README and store text is a paraphrase.
- The widget, controls, Siri and Live Activity exist so that the app need not be
  opened ([overview.md](overview.md)).
- Walking minutes are never zero (`Fountain.walkingMinutes`, 80 m/min, minimum 1).

## 3. One primary action per screen

*One black rectangle says what to do next.*

| Screen | Primary action | Where |
| --- | --- | --- |
| Mapa | "Traçar rota" for the selected fountain | `Toret/Screens/MapScreen.swift` plate |
| Perto | "Ver no mapa" / "Ver mais fontes" | `Toret/Screens/NearbyScreen.swift` |
| Detalhe | the route bar pinned at the bottom | `Toret/Screens/DetailScreen.swift` |
| Review sheet | "Enviar relato" | `Toret/Community/ReviewSheet.swift` |
| Empty states | one action ("Encontrar fontes") | `Toret/Components/EmptyScene.swift` |

Secondary actions are framed outlines with no fill (`SecondaryButton`). Walking is a
full-screen *mode* you leave, not a page you go back from: nothing else competes for
the display while you move (`Route` doc comment in `ToretModel.swift`).

## 4. Shape and colour for water state

*Colour is never the only channel.*

| State | Shape | Ink | Label (pt-BR) |
| --- | --- | --- | --- |
| Running | circle | blu | Água corrente |
| Weak | half-disc | sole, black outline | Fluxo fraco |
| Dry | triangle | rosso | Sem água |
| No recent report | empty ring | inchiostro 55% | Sem relato recente |

`StateMark` (`Shared/DesignSystem/Poster.swift`) draws all four; the map has a legend with a spoken description
(`Toret/Components/Chrome.swift`). The selected pin grows, it does not change colour.
Gaps and caveats: [accessibility.md](accessibility.md).

## 5. The poster as wayfinding

*Identity is functional: where you are is recognisable at a glance.*

- Every tab has a two-line poster title cut for its language (PER/TO, SAL/VAS,
  RELA/TOS, AJUS/TES; see [localization-ux.md](localization-ux.md)).
- The tab bar's yellow sun slides under the active tab (`ToretTabBar`).
- The compass is the only **night** plate: when the background goes dark you are in
  "find it by looking up" mode, with the moon as the dial and Turin's skyline marks
  on the rim.
- Each fountain gets its own deterministic plate from its kind, neighbourhood and
  OSM id, so neighbours differ and a returning user recognises one
  (`Shared/DesignSystem/FountainPlate.swift`).

## 6. Offline-first

*Nothing the user needs waits on the network.*

- The 723-fountain catalogue is in the app bundle; distances, bearings, compass,
  map pins and search are computed on the device.
- Reports appear at once, queue on the device and upload when the network returns
  (`Toret/Community/Community.swift`: optimistic, `NWPathMonitor`).
- The feed and the weather are cached on disk and kept when a refresh fails; the
  screen says "Sem conexão: mostrando os últimos relatos baixados."
  (`CommunityNotice` in `Toret/Community/CommunitySection.swift`).
- The walking route is the straight line until MapKit answers, so the screen is
  useful the instant it opens (`RouteScreen`, `WalkingRoute(to:)`).
- Requests give up after 10 seconds (`APIClient`).

## 7. Calm motion

*Printed things slide and snap; they do not glow.*

- Curves and springs live in one place, `Shared/DesignSystem/Motion.swift`; each has a
  Reduce Motion variant that is a short ease-out (0.16 s) or a cut.
- The needle swings the short way round (`needleAngle` is accumulated, not reduced
  to 0-360).
- One orchestrated moment: the launch poster, about 1.15 s, once per process, skipped
  with Reduce Motion (`Toret/Screens/LaunchOverlay.swift`).
- Looping motion is limited: the river stripes (only while a scene is moving) and the
  slow bob/march of the empty-state scenes. Both stop under Reduce Motion
  (`Shared/DesignSystem/EmptyScenes.swift`, `ParallaxScene.swift`). The poster
  document says only the river loops; the empty scenes are an addition.
- The tilt parallax stops under Reduce Motion and Low Power Mode
  (`Toret/State/TiltProvider.swift`).

## 8. No dark patterns

- No account, no ad, no purchase, no streaks, no counters that invite return.
- Permissions are asked in context. The notification prompt and the step up from
  "while using" to "always" location only appear after the user flips the alert switch
  (`ProximityAlerts.authorise(asking:)`); startup never asks. Note the switches default
  to *on*, so in Ajustes they can read on while the system permission is still "Ainda
  não perguntadas"; nothing fires until the user toggles once.
- Rate limit of one report per fountain per device per 30 minutes keeps feeds honest
  (`Community.rateLimit`); a short note is checked for contact details and abuse
  (`NoteFilter`).
- Safety for user content is built in: flag, block, delete your own
  ([../community-moderation.md](../community-moderation.md)).
- The app is gentle with failure: a missing catalogue says so
  (`CatalogueMissing`), a refused permission has its own sentence per case.

## Checklist for a new screen

1. One question answered by one figure or sentence.
2. One primary button; everything else is outline.
3. State is a shape plus a word, with its source and age.
4. Works offline; says what it is showing when stale.
5. Poster title cut per language; sentence case elsewhere.
6. Reduce Motion variant, VoiceOver label, 44 pt target ([accessibility.md](accessibility.md)).
