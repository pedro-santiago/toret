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

The rest of the repository (source code) is MIT licensed; see `LICENSE`.
