#!/usr/bin/env python3
"""Writes explicit pt-BR values into Localizable.xcstrings.

The catalogue's keys are the Portuguese source strings, and the development
region is English so that a device in German or Spanish falls back to English.
Xcode leaves a key out of pt-BR.lproj when its value would equal the key, and
an NSBundle that cannot find a key in the user's language falls back to the
development region: a Portuguese device would then show English. Writing the
pt-BR value out explicitly makes Xcode emit the table.

    tools/fill-source-language.py [catalog]   (default Shared/Resources/Localizable.xcstrings)

Keys that carry plural/device variations are listed and left alone: their pt-BR
forms are not derivable from the key.
"""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "Shared/Resources/Localizable.xcstrings"
catalog = json.load(open(path))
added, skipped = 0, []
for key, entry in catalog["strings"].items():
    localizations = entry.setdefault("localizations", {})
    if "pt-BR" in localizations or entry.get("shouldTranslate") is False:
        continue
    if any("variations" in loc for loc in localizations.values()):
        skipped.append(key)
        continue
    localizations["pt-BR"] = {"stringUnit": {"state": "translated", "value": key}}
    added += 1
with open(path, "w") as handle:
    json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
print(f"added {added} pt-BR values; left {len(skipped)} with variations: {skipped}")
