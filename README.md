# Toret

Find Turin's public drinking fountains: a compass, a map, widgets and a
community feed. iOS 26, SwiftUI. Free, no ads, no tracking.

> **Status:** work in progress toward 1.0. `main` may be mid-refactor until the
> 1.0 tag, and a few features below are still being built. It is not on the App
> Store yet.

Turin has public drinking water on almost every corner. The best known are the
*toret*, the cast-iron bull's-head columns that have served the city since the
19th century. Toret finds the nearest fountain and walks you to it.

<!-- TODO: screenshots, once the poster redesign has landed. -->

## Honest by design

The catalogue is real: **723 public drinking fountains** inside the Turin
municipality, **184 of them classic toret**, taken from OpenStreetMap and bundled
in the app, so it works offline.

What the app does **not** know is whether the water is running. Nobody publishes
that. So a fountain shows "sem relato recente" until someone standing at it says
otherwise, and a report goes stale after 36 hours. The app never says water is
running without a dated community report behind it.

## Features

Built:

- **Compass**: the needle points at the fountain, and the ring is labelled with
  things you can see from the street. Instead of "296°" it says "olhe entre a
  Mole e Superga".
- **Map**: every fountain, drawn only where you are looking, with search by
  street, square or neighbourhood and filters for step-free access, bottle
  filling and dogs.
- **Perto de mim**: fountains sorted by distance.
- **Walking route**: one instruction at a time, from MapKit directions.
- **Saved fountains** and an optional alert within 100 m of one.
- **Edge cases said out loud**: no location permission, a fix outside Turin or
  a reduced-accuracy fix each get a visible explanation instead of a quiet
  fallback.

In progress (see the `Toret/Community` and `ToretWidgets` folders):

- **Community**: rate a fountain, report the water, read the feed. Offline-first,
  anonymous, stored in the CloudKit public database. Report, block and delete
  are built in.
- **Widgets and system integration**: home and lock-screen widgets, a Live
  Activity for the walk, Control Center controls, Siri and Shortcuts.

## Design

A flat Bauhaus travel poster of Turin: cream stock, black League Spartan titles
cut over two lines, and a handful of flat yellow, red and blue shapes. No glass,
gradients or shadows. Water state is a shape, so colour is never the only
signal: a blue circle for running, a yellow half-disc for weak, a red triangle
for dry, an empty ring for no report.

## Architecture

```
Shared/          Model, design system and components used by the app and widgets
  Model/         Fountain, Catalogue, Report, Landmark, WalkingRoute, Store
  DesignSystem/  Palette, Typography, Poster shapes, Motion
  Resources/     fountains.json, the bundled catalogue
Toret/           The app: screens, state, community, intents
ToretWidgets/    Widgets and the Live Activity
ToretTests/      Swift Testing suites (bearings, catalogue, community, model)
tools/           build-catalogue.py, TestFlight export options
docs/            Privacy and support pages, App Store metadata
```

The app and the widgets share an app group (`group.br.tec.nuance.toret`) for
the saved fountains and the last measured position.

### The catalogue

`tools/build-catalogue.py` asks the public Overpass API for every
`amenity=drinking_water` in the municipality, names each point after the nearest
street and neighbourhood, and writes `Shared/Resources/fountains.json`. Answers
are cached in `build/osm/`.

## Build and run

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
make run      # build and launch on the simulator, located in Turin
make test     # run the unit tests
make device   # build, sign and install on a connected iPhone
make help     # everything else
```

`make run` and `make test` regenerate `Toret.xcodeproj` from `project.yml`.

### Signing

- **Device builds on a free Personal Team** can't provision the App Groups
  capability. Use `make device GROUPS=NO`: the app works, but widgets can't read
  its position and fall back to central Turin.
- **Archive and TestFlight** need an App Store Connect API key. Copy
  `local.mk.example` to `local.mk` (it is gitignored), fill it in, and put the
  `.p8` file in `~/.appstoreconnect/private_keys/`. Never commit either.
  `make testflight UPLOAD=NO` rehearses the export without uploading.

## Languages

Toret speaks Brazilian Portuguese, English and Italian, and follows the device:
the system picks the language from your preferred-languages list, and iOS Settings
→ Toret → Language switches it per app. Any other language (German, Spanish...) falls
back to English; Portuguese from Portugal gets Portuguese; Swiss Italian gets Italian.
Distances are metric everywhere, since the fountains are in Italy. How it is built,
how to add a string and how to check the translations: [`docs/localization.md`](docs/localization.md).

## Privacy

Your location stays on your device: it orders the list, points the needle and
arms the 100 m alert, and nothing is sent to a server. No account, no analytics,
no tracking. Community reports are public and carry no name, email or position.
Maps come from Apple Maps. See [`docs/privacy`](docs/privacy/index.html) and
[`docs/support`](docs/support/index.html).

## Contributing

Issues and pull requests are welcome; see [`CONTRIBUTING.md`](CONTRIBUTING.md).
To fix fountain data, fix it in OpenStreetMap and rebuild the catalogue.

## Licences

- **Source code**: [MIT](LICENSE).
- **Fountain data**: ODbL 1.0, © OpenStreetMap contributors.
  See [`DATA-LICENSE.md`](DATA-LICENSE.md).
- **Fonts**: League Spartan and Archivo, SIL OFL 1.1.
- **Artwork** (icon and illustrations): CC BY 4.0, © 2026 Pedro Santiago.

Details in [`THIRD-PARTY.md`](THIRD-PARTY.md). App Store copy lives in
[`docs/appstore`](docs/appstore/metadata.md).
