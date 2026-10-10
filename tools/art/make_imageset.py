#!/usr/bin/env python3
"""Adds a single-scale PNG to the asset catalogue as <name>.imageset.

    python3 tools/art/make_imageset.py <name> <file.png> [--template]

Only ever creates a new .imageset folder; it never touches AppIcon or colour sets.
`--template` marks the image as a template, for one-colour glyphs.
"""
import json
import os
import shutil
import sys

name, src = sys.argv[1], sys.argv[2]
template = "--template" in sys.argv
catalogue = os.path.join(os.path.dirname(__file__), "..", "..", "Toret", "Resources", "Assets.xcassets")
folder = os.path.join(catalogue, f"{name}.imageset")
os.makedirs(folder, exist_ok=True)
file = f"{name}.png"
shutil.copyfile(src, os.path.join(folder, file))
contents = {"images": [{"filename": file, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
if template:
    contents["properties"] = {"template-rendering-intent": "template"}
json.dump(contents, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
print("wrote", os.path.normpath(folder))
