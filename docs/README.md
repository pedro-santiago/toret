# Toret documentation

Toret is a free iOS 26 app (SwiftUI) that finds Turin's public drinking fountains,
walks you to one and lets the community report the water. The top-level
[`README.md`](../README.md) is the short version; this folder is the detail.

## The app: what it is and how it behaves

| Doc | What it covers |
| --- | --- |
| [app/overview.md](app/overview.md) | What Toret is, who it is for, the five tabs, every surface outside the app, boundaries, a screen map and an honest build status |
| [app/ux-principles.md](app/ux-principles.md) | The UX principles the screens embody, tied to concrete components |
| [app/architecture.md](app/architecture.md) | Targets, state ownership, location, catalogue, community stack, widgets and the app group, build and tests |
| [app/data-and-honesty.md](app/data-and-honesty.md) | Where every datum comes from and exactly what the app may claim about it |
| [app/navigation.md](app/navigation.md) | Tab bar, per-tab stacks, `toret://` deep links, Debug launch arguments, what is restored |
| [app/accessibility.md](app/accessibility.md) | VoiceOver, Dynamic Type, Reduce Motion, measured contrast, hit targets, haptics and the gaps |
| [app/localization-ux.md](app/localization-ux.md) | What a pt-BR, English or Italian user sees: selection, re-cut poster titles, formatting |
| [app/glossary.md](app/glossary.md) | Terms: toret, fonte, Mole, Perto, relato, handle, install token, plate, parallax... |

## Screen by screen

One document per screen or surface: purpose, layout, states, interactions, copy.

| Doc | Screen |
| --- | --- |
| [app/screens/map.md](app/screens/map.md) | Mapa: the map, pins, search, filters, the selected-fountain plate |
| [app/screens/nearby.md](app/screens/nearby.md) | Perto: the nearest fountains as a list |
| [app/screens/compass.md](app/screens/compass.md) | Bússola: the night-plate compass |
| [app/screens/detail.md](app/screens/detail.md) | A fountain's page |
| [app/screens/route.md](app/screens/route.md) | Walking route, full screen |
| [app/screens/community.md](app/screens/community.md) | Relatos: the feed, reporting, blocking; the review sheet |
| [app/screens/saved.md](app/screens/saved.md) | Salvas: saved fountains |
| [app/screens/settings.md](app/screens/settings.md) | Ajustes: switches, permissions, credits |
| [app/screens/launch.md](app/screens/launch.md) | The launch poster and first-run behaviour |
| [app/screens/system-surfaces.md](app/screens/system-surfaces.md) | Widgets, Live Activity, controls, Siri and Shortcuts, the proximity notification |
| [app/screens/empty-states.md](app/screens/empty-states.md) | Empty and edge states and their drawn scenes |

## Design

| Doc | What it covers |
| --- | --- |
| [design/poster-system.md](design/poster-system.md) | The flat Bauhaus Turin-poster identity: inks, type, shapes, components, fountain plates, motion, copy |

## Server and community

| Doc | What it covers |
| --- | --- |
| [backend/api.md](backend/api.md) | The community API v1: the contract the Swift client and the Go Lambda implement |
| [backend/openapi.yaml](backend/openapi.yaml) | Machine-readable twin of the API contract (api.md wins on a disagreement) |
| [community-moderation.md](community-moderation.md) | Running the server and moderating reports |

## Privacy, support and the store

| Doc | What it covers |
| --- | --- |
| [privacy/index.html](privacy/index.html) | The privacy policy page, hosted at toret.deepdive.dev.br/privacy/ |
| [support/index.html](support/index.html) | The support page, hosted at toret.deepdive.dev.br/support/ |
| [appstore/metadata.md](appstore/metadata.md) | App Store Connect text, ratings and privacy-label answers, in three languages |
| `appstore/screenshots/<language>/` | Store screenshots per language (pt-BR, en, it) |
| [localization.md](localization.md) | How strings are written, merged and checked; vocabulary; how to add a language |

## Images

`images/` holds the README banner, the architecture and data-flow diagrams and four
screen captures used by the top-level README.

## Elsewhere in the repository

| File | What it covers |
| --- | --- |
| [`../README.md`](../README.md) | Project overview and build instructions |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | How to contribute |
| [`../DATA-LICENSE.md`](../DATA-LICENSE.md) | ODbL terms for the catalogue; Open-Meteo and SMAT status |
| [`../DISTRIBUICAO.md`](../DISTRIBUICAO.md) | What remains before the App Store (pt-BR) |
| [`../THIRD-PARTY.md`](../THIRD-PARTY.md) | Third-party credits |
| [`../backend/README.md`](../backend/README.md) | Building, testing and deploying the server |
