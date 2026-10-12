# Third-party material

| What | Where | Licence |
| --- | --- | --- |
| Fountain positions and names | `Shared/Resources/fountains.json` | ODbL 1.0, © OpenStreetMap contributors. See `DATA-LICENSE.md`. |
| League Spartan (titles and figures) | `Toret/Resources/Fonts/LeagueSpartan.ttf` | SIL Open Font License 1.1. See `Toret/Resources/Fonts/OFL-LeagueSpartan.txt`. © 2020 The League Spartan Project Authors. |
| Archivo (interface text) | `Toret/Resources/Fonts/Archivo.ttf` | SIL Open Font License 1.1. See `Toret/Resources/Fonts/OFL-Archivo.txt`. |
| FLUX.2 [klein] 4B (4-bit MLX build `mlx-community/flux2-klein-4b-4bit`), run locally with mflux | Used to draw the base of `art-toret*` and `art-skyline-*`, and the 13 subject plates `plate-*` (the fountain objects of the per-fountain illustrations), in the asset catalogue; no weights or code are redistributed. Prompts and seeds in `tools/art/PROMPTS.md` | Apache License 2.0 (model licence permits commercial use of outputs). The generated images are then palette-quantised, retouched and, for the sun, repainted; the `plate-*` subjects are keyed off their ground, outlined and palette-locked by `tools/art/key_subject.py`. |
| Weather: temperature, apparent temperature and humidity for Turin | Fetched by the backend (`backend/internal/weather`) from the Open-Meteo API and relayed by `GET /v1/conditions`; the app never contacts Open-Meteo. Shown with its attribution and time on the Nearby screen, with a link in Settings | [Open-Meteo.com](https://open-meteo.com/) data, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): "Weather data by Open-Meteo.com". The free API is for **non-commercial use only**: a paid plan is needed if the app ever earns money. See `DATA-LICENSE.md`. |
| SMAT works notices (Mappa Cantieri) | **Not used.** The backend has an ingest for them behind a flag (`SmatEnabled`, off), because SMAT publishes no licence for the data and there is no written permission. Nothing of SMAT's is fetched, stored or shown while it is off. | None granted. Do not switch it on without SMAT's written permission. |
| MapKit, CoreLocation, WidgetKit, ActivityKit, App Intents | Linked from the OS | Apple's SDK terms. No Apple code is redistributed here. |

There are no package-manager dependencies.

## The author's own material

- **Source code**: MIT, see `LICENSE`.
- **Artwork**: the app icon and the poster-style illustrations in
  `Toret/Resources/Assets.xcassets` (and the drawn shapes in
  `Shared/DesignSystem/`, which are code and therefore MIT) are © 2026 Pedro
  Santiago. The image assets are licensed
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); you may reuse them
  with credit.
- **Name**: "Toret" as the name of the App Store app is not licensed for use on
  a derivative app; pick your own name if you publish a fork.
