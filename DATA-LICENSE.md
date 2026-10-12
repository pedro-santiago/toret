# Data licence: the fountain catalogue

`Shared/Resources/fountains.json` is a **Derived Database** of data from
[OpenStreetMap](https://www.openstreetmap.org). It lists every point tagged
`amenity=drinking_water` inside the municipality of Turin, with the street and
neighbourhood names worked out from other OpenStreetMap features.

> © OpenStreetMap contributors

The file is made available under the **Open Database License (ODbL) 1.0**, not
under this repository's MIT licence:

- Licence text: <https://opendatacommons.org/licenses/odbl/1-0/>
- Attribution and copyright notice: <https://www.openstreetmap.org/copyright>

If you reuse the file, you must credit OpenStreetMap contributors, keep the
file (and any database you build from it) under the ODbL, and say so. The app
shows the attribution in its Settings screen.

## Rebuilding it

The file is generated, not hand-edited:

```sh
python3 tools/build-catalogue.py
```

The script queries the public Overpass API, caches the answers in `build/osm/`,
and rewrites `fountains.json`. To correct a fountain, fix it in OpenStreetMap
and rebuild; changes made only in this repository's copy are overwritten.

## Other data the app shows

- **Weather: Open-Meteo.** The temperature on the Nearby screen is data from
  [Open-Meteo.com](https://open-meteo.com/), licensed
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The Toret backend
  fetches it (for one point in central Turin, at most every 15 minutes) and the
  app shows it with the credit "Open-Meteo", the time of the reading, and a link
  in Settings; it is never stored in this repository. Open-Meteo's free API is for
  **non-commercial use only**: if the app ever earns money, a paid plan is
  required first.
- **SMAT works notices: not used.** SMAT S.p.A. (Mappa Cantieri) publishes no
  licence for its works data, so nothing of it is used: the backend feature is
  switched off (`SmatEnabled=false`) and stays off until SMAT gives written
  permission.
- **Community reports** are written by the app's users, not taken from any
  source, and are deleted after 30 days. They are not part of this repository.

The rest of the repository (source code) is MIT licensed; see `LICENSE`.
