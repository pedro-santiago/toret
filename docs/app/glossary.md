# Glossary

Terms as the app, the code and the design use them. pt-BR is the source language of the
interface; en and it where they differ. See also [../localization.md](../localization.md)
for the translation vocabulary.

## People and places

| Term | Meaning |
| --- | --- |
| **toret** (also *toretto*, a generic OSM name) | The cast-iron bull's-head drinking column that has served Turin since the 19th century. 184 of the 723 catalogue entries are `kind: toret`. The app is named after it. |
| **fonte** (it: *fontanella*, en: fountain) | The interface word for any public drinking fountain, toret or not. Italian never uses *fonte* (a spring). In code the type is `Fountain`. |
| **fontanella** | Italian for the same thing; also one of the generic OSM names the app replaces with the street name. |
| **Turim / Torino / Turin** | The city; the catalogue covers the municipality only. |
| **Mole** (Mole Antonelliana) | Turin's landmark spire, a skyline mark on the compass rim and the map, and the shape of `MoleSilhouette`. |
| **Superga** | The basilica on the hill east of the city, another compass landmark. |
| **Piazza San Carlo / the anchor** | `Catalogue.anchor` (45.06687, 7.68316). Distances are measured from here when there is no usable fix. |
| **Catalogue** (*catálogo*) | The 723 fountains in `Shared/Resources/fountains.json`, from OpenStreetMap. |
| **Zone / neighbourhood** (*bairro*) | One of 35 named neighbourhoods (`Fountain.zone`); picks the backdrop of a fountain's plate. |

## Tabs and screens

| Term | Meaning |
| --- | --- |
| **Mapa** | Map tab. en Map, it Mappa. |
| **Perto** ("close") | Nearby tab; its poster title is PER/TO. en Nearby, it Vicino. |
| **Relatos** | The community feed tab. en Reports, it Segnalazioni. |
| **Salvas** | Saved fountains tab. en Saved, it Salvate. |
| **Ajustes** | Settings tab. it Opzioni. |
| **Bússola** | The compass screen (night plate, the moon as the dial). |
| **Rota** | The walking route, a full-screen mode. "Traçar rota": get the route. |
| **Detalhe / a fonte** | A fountain's own page ("Fonte" in the screen docs). |
| **Avaliar** | To rate/review; the review sheet is "AVALIAR". |
| **Obrigado** | The thank-you plate shown after a report is sent. |

## Water and reports

| Term | Meaning |
| --- | --- |
| **Relato** (en report, it segnalazione) | One person's word about one fountain: state, optional rating, up to 3 tags, a note of up to 140 characters. `Report`. The sheet that writes one is titled AVALIAR ("rate this"). |
| **Avaliação** | A star-style rating, 1 to 5 diamonds. |
| **Water state** | `WaterState`: `running`, `weak`, `dry`, `unknown`. Palette aliases `corrente`, `debole`, `secca`, `ignota`. |
| **Água corrente** | Running: a blue circle. |
| **Fluxo fraco** | Weak flow: a yellow half-disc with a black outline. |
| **Sem água** (shorter "Seca") | Dry: a red triangle. |
| **Sem relato recente** (short "Sem relato") | No fresh report: an empty ring. The honest default. |
| **Freshness** | 36 hours: how long a state report is believed. After that the state is `unknown`. |
| **Summary** | `CommunitySummary`: what a fountain's reports add up to (state, latest date, average, counts). |
| **Provenance** | The line saying where a state comes from and how old it is: "Relato há 2 h". |
| **Sazonal** | Seasonal: switched off in winter, so no water between November and March may not be a fault. |
| **Handle** | The anonymous public name of a device: "Visitante" plus 6 hex digits, derived by SHA-256 from the install token (`AuthorHandle`). Blocking is by handle. |
| **Install token** | A random 16-64 character code in the Keychain that stands for this install on the server. The server stores only a keyed hash. There are no accounts. |
| **Denunciar / Bloquear** | Flag a report / block an author; both hide content on this device at once. |
| **Rate limit** | One report per fountain per device per 30 minutes. |
| **Queue** | Reports and deletions waiting on the device until the network allows upload. |

## Location and sensors

| Term | Meaning |
| --- | --- |
| **Fix** | One measured position from Core Location. |
| **LocationStatus** | The reason distances are what they are: `asking`, `searching`, `live`, `approximate`, `denied`, `restricted`, `outsideTurin`. |
| **Bearing** | Direction from the user to the fountain, degrees clockwise from north. |
| **Heading** | The direction the phone faces. The dial turns with it only if it is accurate to 35 degrees. |
| **Needle** | The black triangle on the compass; its angle is accumulated so it turns the short way. |
| **Origin** | The point the model measures from (the user or the anchor). |
| **Geofence / proximity alert** | A 100 m ring round each of the nearest 8 fountains; entering one raises "Fonte a 100 m". |
| **App group** | `group.br.tec.nuance.toret`, the storage shared by app and widgets. |
| **Live Activity** | The walk shown on the Lock Screen and in the Dynamic Island. |
| **Deep link** | A `toret://` URL ([navigation.md](navigation.md)). |

## Design

| Term | Meaning |
| --- | --- |
| **Poster** | The visual identity: a flat mid-century Turin travel poster. See [../design/poster-system.md](../design/poster-system.md). |
| **Ink** | A palette colour: *carta* (cream stock), *inchiostro* (black ink), *sole* (sun yellow), *rosso* (red), *blu* (river blue), *salvia* (Alps), *notte* (night), *luna* (moon). |
| **Plate** (UI) | An opaque rectangle with a 2.5 pt black frame that replaces cards and panes (`.plate()`; the legacy modifier names `glassPane` and `glassCapsule` still exist). |
| **Plate** (fountain) | `FountainPlate`: a small deterministic poster composed from a fountain's kind, neighbourhood and id; it never draws water. |
| **Plate** (number) | The operator's number on a toret, OSM `ref`. `plateTitle` reads "Toret n. 69442". |
| **PosterTitle** | The giant two-line uppercase title with a black rule at its left edge: RELA/TOS. |
| **StateMark** | The component that draws the four water-state shapes. |
| **Sun / SunDisc** | The yellow disc that slides behind the active tab and sits behind titles. |
| **Skyline** | The drawn landmark library (`Shared/DesignSystem/Skyline/`). |
| **Parallax** | Depth layers of the poster scene (Alps, city, Mole, river) that shift with scroll and phone tilt (`ParallaxScene`, `TiltProvider`). Off under Reduce Motion. |
| **Empty scene** | A drawn poster scene for an empty or edge state (no saved fountains, no connection...). |
| **Launch overlay** | The one orchestrated moment: the poster assembles on a cold start, about 1.15 s. |

## Data and legal

| Term | Meaning |
| --- | --- |
| **OSM / OpenStreetMap** | Source of the catalogue; `(c) OpenStreetMap contributors`. |
| **ODbL** | Open Database License 1.0 that governs the catalogue file. |
| **Node id** | The OpenStreetMap node number, used as `Fountain.id` and in `toret://fountain/<id>`. |
| **Overpass** | The OpenStreetMap query API used by `tools/build-catalogue.py`. |
| **Open-Meteo** | Weather source (CC BY 4.0, non-commercial free tier). Context only. |
| **SMAT** | Turin's water utility. Its works notices are implemented but switched off for lack of a licence. |
| **Conditions** | The server's `/v1/conditions`: weather plus (off) works notices. |
| **Backend / server** | The Go Lambda and DynamoDB at `https://torino.deepdive.dev.br` ([../backend/api.md](../backend/api.md)). |
