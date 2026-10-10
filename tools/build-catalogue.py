#!/usr/bin/env python3
"""Builds Shared/Resources/fountains.json from OpenStreetMap.

    tools/build-catalogue.py [cache-dir]

Every point is an OSM node tagged amenity=drinking_water inside the Turin
municipality. Street and neighbourhood names are derived here, once, so the app
needs no network and no geocoder: the street is the nearest named way within 80 m,
the neighbourhood is the nearest OSM suburb/quarter node within 1.5 km.

Data (c) OpenStreetMap contributors, ODbL: https://www.openstreetmap.org/copyright
The app shows that attribution in Ajustes. Overpass responses are cached in
cache-dir (default build/osm) so a rebuild does not hit the public server again.
"""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

BBOX = "44.99,7.57,45.14,7.78"
UA = "Toret-build/1.0 (contato@pedrosantiago.com.br)"
OVERPASS = "https://overpass-api.de/api/interpreter"
OUT = os.path.join(os.path.dirname(__file__), "..", "Shared", "Resources", "fountains.json")

QUERIES = {
    "water.json": f'[out:json][timeout:100];node["amenity"="drinking_water"]({BBOX});out tags center;',
    "inturin.json": '[out:json][timeout:100];area["name"="Torino"]["admin_level"="8"]["boundary"="administrative"]->.t;'
                    'node["amenity"="drinking_water"](area.t);out ids;',
    "places.json": f'[out:json][timeout:100];node["place"~"suburb|quarter"]({BBOX});out body;',
    "streets.json": f'[out:json][timeout:160];way["highway"]["name"]({BBOX});out geom tags;',
}


def fetch(cache, name):
    path = os.path.join(cache, name)
    if os.path.exists(path):
        return json.load(open(path))
    data = urllib.parse.urlencode({"data": QUERIES[name]}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(OVERPASS, data=data, headers={"User-Agent": UA})
            body = urllib.request.urlopen(req, timeout=200).read()
            json.loads(body)
            open(path, "wb").write(body)
            return json.loads(body)
        except Exception as error:  # public server: 429/504 are routine
            wait = 20 * (attempt + 1)
            print(f"{name}: {error}; retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    sys.exit(f"could not fetch {name}")


def metres(lat0, lat1, lon0, lon1):
    k = math.cos(math.radians(lat0))
    return math.hypot((lat1 - lat0) * 111_320, (lon1 - lon0) * 111_320 * k)


def segment_distance(lat, lon, a, b):
    """Metres from a point to the segment a-b, on a local flat projection."""
    k = math.cos(math.radians(lat))
    ax, ay = (a["lon"] - lon) * 111_320 * k, (a["lat"] - lat) * 111_320
    bx, by = (b["lon"] - lon) * 111_320 * k, (b["lat"] - lat) * 111_320
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0 if length2 == 0 else max(0, min(1, -(ax * dx + ay * dy) / length2))
    return math.hypot(ax + t * dx, ay + t * dy)


def main():
    cache = sys.argv[1] if len(sys.argv) > 1 else "build/osm"
    os.makedirs(cache, exist_ok=True)

    water = fetch(cache, "water.json")["elements"]
    inside = {e["id"] for e in fetch(cache, "inturin.json")["elements"]}
    places = [
        (e["lat"], e["lon"], e["tags"]["name"])
        for e in fetch(cache, "places.json")["elements"]
        if "name" in e["tags"] and "(" not in e["tags"]["name"]
    ]
    streets = fetch(cache, "streets.json")["elements"]

    # Bucket street segments by 0.002-degree cell so each lookup touches a handful.
    cell = 0.002
    grid = {}
    for way in streets:
        geometry = way.get("geometry") or []
        for a, b in zip(geometry, geometry[1:]):
            for cx in range(int(a["lon"] / cell) - 1, int(a["lon"] / cell) + 2):
                for cy in range(int(a["lat"] / cell) - 1, int(a["lat"] / cell) + 2):
                    grid.setdefault((cx, cy), []).append((way["tags"]["name"], a, b))

    def street_for(lat, lon):
        best, best_d = None, 80
        for name, a, b in grid.get((int(lon / cell), int(lat / cell)), []):
            d = segment_distance(lat, lon, a, b)
            if d < best_d:
                best, best_d = name, d
        return best

    def zone_for(lat, lon):
        best, best_d = None, 1500
        for plat, plon, name in places:
            d = metres(lat, plat, lon, plon)
            if d < best_d:
                best, best_d = name, d
        return best

    kinds = {"toret": "toret", "bubbler": "bubbler", "bottle_refill": "refill"}
    out = []
    skipped = {"outside": 0, "private": 0, "indoor": 0, "fee": 0}
    for e in water:
        tags = e.get("tags", {})
        if e["id"] not in inside:
            skipped["outside"] += 1
            continue
        if tags.get("access") in ("private", "customers", "no", "permit"):
            skipped["private"] += 1
            continue
        if tags.get("indoor") == "yes":
            skipped["indoor"] += 1
            continue
        if tags.get("fee") == "yes":
            skipped["fee"] += 1
            continue
        lat, lon = e["lat"], e["lon"]
        item = {
            "id": str(e["id"]),
            "lat": round(lat, 6),
            "lon": round(lon, 6),
            "kind": kinds.get(tags.get("fountain"), "fountain"),
        }
        street, zone = street_for(lat, lon), zone_for(lat, lon)
        for key, value in (
            ("name", tags.get("name")),
            ("street", street),
            ("zone", zone),
            ("ref", tags.get("ref")),
            ("wheelchair", tags.get("wheelchair") if tags.get("wheelchair") in ("yes", "limited", "no") else None),
            ("bottle", True if tags.get("bottle") == "yes" else None),
            ("dog", True if tags.get("dog") == "yes" else None),
            ("seasonal", True if tags.get("seasonal") in ("yes", "summer") else None),
            ("checked", tags.get("check_date")),
        ):
            if value is not None:
                item[key] = value
        out.append(item)

    out.sort(key=lambda f: int(f["id"]))
    with open(OUT, "w") as handle:
        json.dump(out, handle, ensure_ascii=False, separators=(",", ":"))
    named = sum(1 for f in out if "street" in f or "name" in f)
    print(f"{len(out)} fountains ({named} with a name or street); skipped {skipped}; -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
