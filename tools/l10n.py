#!/usr/bin/env python3
"""Merges translations into the String Catalogs.

    tools/l10n.py merge  [file.json ...]   apply tools/l10n/*.json to Shared/Resources/Localizable.xcstrings
    tools/l10n.py merge-plist app|widget   apply tools/l10n/infoplist-*.json to the InfoPlist catalogs
    tools/l10n.py merge-shortcuts          apply tools/l10n/appshortcuts.json (Siri phrase sets) to AppShortcuts.xcstrings
    tools/l10n.py sync [derived-data]      add the literals the compiler found (build first) and mark vanished ones stale
    tools/l10n.py missing                  print the keys that still lack en or it

A translations file is a JSON object, key (the Portuguese source text, with
%@ / %lld in the places Swift interpolates) to {"en": "...", "it": "..."}.
Plurals: {"plural": {"pt-BR": {"one": "...", "other": "..."}, "en": {...}, "it": {...}}}.
Positional specifiers (%1$@) are allowed when a language needs another word order.

Why a script and not the Xcode editor: the translations are reviewed in the diff of
a small JSON file, a build can add keys to the catalog but cannot translate them,
and the same file feeds tools/check-localization.py.
"""
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOG = os.path.join(ROOT, "Shared", "Resources", "Localizable.xcstrings")
LANGS = ("pt-BR", "en", "it")


def load(path, default_source="pt-BR"):
    if os.path.exists(path):
        return json.load(open(path))
    return {"sourceLanguage": default_source, "strings": {}, "version": "1.0"}


def save(path, catalog):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        # Xcode's own formatting: two-space indent, a space before the colon.
        json.dump(catalog, handle, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
        handle.write("\n")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def apply(entry, translations):
    locs = entry.setdefault("localizations", {})
    if "plural" in translations:
        for lang, forms in translations["plural"].items():
            locs[lang] = {"variations": {"plural": {cat: unit(text) for cat, text in forms.items()}}}
    for lang in LANGS:
        if lang in translations:
            locs[lang] = unit(translations[lang])


def merge(files):
    catalog = load(CATALOG)
    for path in files:
        for key, translations in json.load(open(path)).items():
            apply(catalog["strings"].setdefault(key, {}), translations)
    save(CATALOG, catalog)
    print(f"{len(catalog['strings'])} keys in {os.path.relpath(CATALOG, ROOT)}")


SHORTCUTS = os.path.join(ROOT, "Toret", "Resources", "AppShortcuts.xcstrings")


def merge_shortcuts():
    """Siri phrases are sets, not strings: one entry per AppShortcut, keyed by its
    first phrase, with a list of phrases per language (each must name the app)."""
    catalog = load(SHORTCUTS)
    for key, languages in json.load(open(os.path.join(ROOT, "tools", "l10n", "appshortcuts.json"))).items():
        entry = catalog["strings"].get(key)
        if entry is None:
            print(f"skipped (no such shortcut in the code any more): {key!r}")
            continue
        for lang, phrases in languages.items():
            entry.setdefault("localizations", {})[lang] = {"stringSet": {"state": "translated", "values": phrases}}
        pt = entry["localizations"].get("pt-BR", {}).get("stringSet")
        if pt:
            pt["state"] = "translated"
    save(SHORTCUTS, catalog)
    print(f"{len(catalog['strings'])} shortcuts in {os.path.relpath(SHORTCUTS, ROOT)}")


PLIST = {
    "app": os.path.join(ROOT, "Toret", "Resources", "InfoPlist.xcstrings"),
    "widget": os.path.join(ROOT, "ToretWidgets", "InfoPlist.xcstrings"),
}


def merge_plist(target):
    path = PLIST[target]
    catalog = load(path, default_source="en")
    for key, translations in json.load(open(os.path.join(ROOT, "tools", "l10n", f"infoplist-{target}.json"))).items():
        apply(catalog["strings"].setdefault(key, {}), translations)
    save(path, catalog)
    print(f"{len(catalog['strings'])} keys in {os.path.relpath(path, ROOT)}")


def sync(derived):
    """Folds the compiler's .stringsdata (app + widget) into the catalog.

    Both targets are passed together, because they share one catalog: syncing with
    only the app's data would mark every widget-only string stale.
    """
    derived = derived or os.path.join(ROOT, "build", "i18n")
    files = []
    for target in ("Toret.build", "ToretWidgetsExtension.build"):
        for base, _, names in os.walk(os.path.join(derived, "Build", "Intermediates.noindex", target)):
            files += [
                os.path.join(base, n) for n in names
                if n.endswith(".stringsdata") and not n.startswith("ExtractedAppShortcuts")
            ]
    if not files:
        sys.exit(f"no .stringsdata under {derived}: build with SWIFT_EMIT_LOC_STRINGS=YES first")
    command = ["xcrun", "xcstringstool", "sync", CATALOG]
    for path in files:
        command += ["--stringsdata", path]
    subprocess.run(command, check=True)
    shortcuts = [
        os.path.join(base, n)
        for base, _, names in os.walk(os.path.join(derived, "Build", "Intermediates.noindex", "Toret.build"))
        for n in names if n == "ExtractedAppShortcutsMetadata.stringsdata"
    ]
    if shortcuts:
        command = ["xcrun", "xcstringstool", "sync", SHORTCUTS]
        for path in shortcuts:
            command += ["--stringsdata", path]
        subprocess.run(command, check=True)
    print(f"synced from {len(files)} files and {len(shortcuts)} shortcut files")


def missing():
    catalog = load(CATALOG)
    for key, entry in sorted(catalog["strings"].items()):
        have = set(entry.get("localizations", {}))
        lacking = [lang for lang in ("en", "it") if lang not in have]
        if lacking:
            print(f"{key!r}: {', '.join(lacking)}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "merge":
        merge(sys.argv[2:] or sorted(glob.glob(os.path.join(ROOT, "tools", "l10n", "[!i]*.json"))))
    elif command == "merge-shortcuts":
        merge_shortcuts()
    elif command == "merge-plist" and len(sys.argv) > 2 and sys.argv[2] in PLIST:
        merge_plist(sys.argv[2])
    elif command == "sync":
        sync(sys.argv[2] if len(sys.argv) > 2 else None)
    elif command == "missing":
        missing()
    else:
        sys.exit(__doc__)
