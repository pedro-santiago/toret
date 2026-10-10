#!/usr/bin/env python3
"""Fails when the String Catalogs are not complete and consistent.

    tools/check-localization.py [--allow-stale]

Checks, for Shared/Resources/Localizable.xcstrings and both InfoPlist catalogs:
  * every key has pt-BR (explicit, or implicit for the source language), en and it;
  * no translation is in a state other than "translated" (needs_review, new, stale);
  * no key is marked stale — it no longer appears in the code (--allow-stale skips this);
  * plural entries carry the categories each language needs (en/pt-BR: one + other,
    it: one + other, many optional);
  * the printf-style specifiers (%@, %lld, %1$@ ...) are the same set in every
    language as in the source text, so a translation cannot crash String(format:)
    or silently drop a number.
Run from the repository root or anywhere; exits 1 on any problem.
"""
import glob
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOGS = [
    "Shared/Resources/Localizable.xcstrings",
    "Toret/Resources/InfoPlist.xcstrings",
    "ToretWidgets/InfoPlist.xcstrings",
]
SHORTCUTS = "Toret/Resources/AppShortcuts.xcstrings"
REQUIRED = ("pt-BR", "en", "it")
PLURAL_NEEDED = {"pt-BR": {"one", "other"}, "en": {"one", "other"}, "it": {"one", "other"}}
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaA])")


def specifiers(text):
    """The multiset of conversion types, ignoring order and positional numbering."""
    return Counter(match.group(2).lower() for match in SPECIFIER.finditer(text.replace("%%", "")))


def units(localization):
    """Every stringUnit under a localization, with a label for messages."""
    if "stringUnit" in localization:
        yield "", localization["stringUnit"]
    for category, variation in localization.get("variations", {}).get("plural", {}).items():
        yield f"[{category}]", variation["stringUnit"]


def check(path, allow_stale):
    problems = []
    catalog = json.load(open(os.path.join(ROOT, path)))
    source = catalog.get("sourceLanguage", "en")
    for key, entry in sorted(catalog["strings"].items()):
        where = f"{path}: {key!r}"
        if entry.get("extractionState") == "stale" and not allow_stale:
            problems.append(f"{where}: stale (no longer in the code)")
        if entry.get("shouldTranslate") is False:
            continue
        locs = entry.get("localizations", {})
        for lang in REQUIRED:
            if lang not in locs and lang != source:
                problems.append(f"{where}: missing {lang}")
        reference = specifiers(key) if source == "pt-BR" else None
        for lang, localization in locs.items():
            plural = set(localization.get("variations", {}).get("plural", {}))
            if plural:
                for needed in PLURAL_NEEDED.get(lang, {"other"}):
                    if needed not in plural:
                        problems.append(f"{where}: {lang} plural lacks '{needed}'")
            for label, unit in units(localization):
                if unit.get("state") != "translated":
                    problems.append(f"{where}: {lang}{label} is {unit.get('state')!r}")
                value = unit.get("value", "")
                if not value.strip():
                    problems.append(f"{where}: {lang}{label} is empty")
                if reference is not None and specifiers(value) != reference:
                    problems.append(
                        f"{where}: {lang}{label} has specifiers {dict(specifiers(value))}, source has {dict(reference)}"
                    )
    return problems, len(catalog["strings"])


# Calls where a plain literal does NOT get localized, though it looks as if it
# would: SwiftUI picks the verbatim String overload for `Text(cond ? "A" : "B")`,
# and a `String` parameter never looks anything up. Each needs String(localized:).
PORTUGUESE = re.compile(r'[À-ÿ]|\b(?:fonte|fontes|rota|você|sem|nenhuma|abrir|relato|salv\w*|perto|mapa|toque)\b', re.I)
TERNARY = re.compile(r'(?:Text|accessibilityLabel|accessibilityValue|accessibilityHint)\([^()\n]*\?\s*"([^"\n]+)"\s*:\s*"([^"\n]+)"')


def lint_sources():
    """Static check for the unlocalized-literal traps. Prints file:line for each."""
    problems = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Toret", "**", "*.swift"), recursive=True)
                       + glob.glob(os.path.join(ROOT, "Shared", "**", "*.swift"), recursive=True)
                       + glob.glob(os.path.join(ROOT, "ToretWidgets", "**", "*.swift"), recursive=True)):
        for number, line in enumerate(open(path), 1):
            if line.lstrip().startswith("//"):
                continue
            match = TERNARY.search(line)
            if match and "String(localized" not in line and PORTUGUESE.search(match.group(0)):
                problems.append(f"{os.path.relpath(path, ROOT)}:{number}: ternary of plain literals is not localized; wrap each in String(localized:)")
            if "Locale(identifier:" in line and "Tests" not in path and "Formatting.swift" not in path:
                problems.append(f"{os.path.relpath(path, ROOT)}:{number}: hard-coded Locale; use Formatting or the current locale")
    return problems


def check_shortcuts(path, allow_stale):
    """Siri phrase sets: every language present, translated, and every phrase names the app."""
    problems = []
    catalog = json.load(open(os.path.join(ROOT, path)))
    for key, entry in sorted(catalog["strings"].items()):
        where = f"{path}: {key!r}"
        if entry.get("extractionState") == "stale" and not allow_stale:
            problems.append(f"{where}: stale (no longer in the code)")
        locs = entry.get("localizations", {})
        for lang in REQUIRED:
            if lang not in locs:
                problems.append(f"{where}: missing {lang}")
                continue
            phrases = locs[lang].get("stringSet", {})
            if phrases.get("state") != "translated":
                problems.append(f"{where}: {lang} is {phrases.get('state')!r}")
            for phrase in phrases.get("values", []):
                if "${applicationName}" not in phrase:
                    problems.append(f"{where}: {lang} phrase {phrase!r} does not name the app")
    return problems, len(catalog["strings"])


def main():
    allow_stale = "--allow-stale" in sys.argv
    problems, total = [], 0
    for path in CATALOGS:
        if not os.path.exists(os.path.join(ROOT, path)):
            problems.append(f"{path}: missing")
            continue
        found, count = check(path, allow_stale)
        problems += found
        total += count
    if os.path.exists(os.path.join(ROOT, SHORTCUTS)):
        found, count = check_shortcuts(SHORTCUTS, allow_stale)
        problems += found
        total += count
    else:
        problems.append(f"{SHORTCUTS}: missing")
    problems += lint_sources()
    for line in problems:
        print(line)
    print(f"{total} keys checked, {len(problems)} problems")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
