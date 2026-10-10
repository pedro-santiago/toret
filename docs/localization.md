# Localization

Toret ships in Brazilian Portuguese (`pt-BR`), English (`en`) and Italian (`it`), and
the language follows the device. Nothing in the app asks the user to pick one.

## What the user gets

iOS matches the device's preferred-languages list against what the app declares:

| Device language | Toret speaks |
| --- | --- |
| English (any region) | English |
| Italiano, Italiano (Svizzera) | Italian |
| Português (Brasil) or Português (Portugal) | Portuguese |
| Anything else (Deutsch, Español, Français, 中文...) | **English** |
| A list such as Français, then Italiano | Italian (the first language Toret has) |

Because the app has three languages, iOS Settings → Toret → Language also appears, so
a reader can use Toret in a different language from the rest of the phone.

The fallback is the important decision. The strings in the code are written in
Portuguese, but a German tourist must not get Portuguese: `CFBundleDevelopmentRegion`
and the project's `developmentLanguage` are `en`, so anything unmatched resolves to
English. `ToretTests/LocalizationTests.swift` asserts the matching table above.

## Architecture

**One String Catalog per kind of text, Portuguese as the source language.**

| File | Holds | Target |
| --- | --- | --- |
| `Shared/Resources/Localizable.xcstrings` | Every string in code: `Text("…")`, `String(localized:)`, `LocalizedStringResource`, plurals | app **and** widget extension (Shared is compiled into both) |
| `Toret/Resources/InfoPlist.xcstrings` | Location permission texts | app |
| `ToretWidgets/InfoPlist.xcstrings` | The widget's location permission text | widgets |
| `Toret/Resources/AppShortcuts.xcstrings` | Siri / Spotlight phrases, as phrase *sets* | app |

The keys are the Portuguese text itself. That keeps the code readable (`Text("Perto")`
reads like the screen) and means SwiftUI extracts every literal with no ceremony. The
price is that rewording a Portuguese string orphans its translations; that is caught by
the checker below as a stale key plus a missing translation, never silently.

The alternative, semantic keys (`nearby.title`) with English as the source, makes every
call site an indirection and would have meant rewriting all the interface code. It buys
one real thing: an unfinished translation falls back to English rather than Portuguese.
We get the same safety from `tools/check-localization.py` and the unit tests failing
instead.

`pt-BR` is the catalog's source language, so its entries are implicit (the key is the
value) except where it has plural forms. `en` and `it` are explicit everywhere.

### Where the translations are written

Translations live in small JSON files under `tools/l10n/` and are merged into the
catalogs by `tools/l10n.py`. A build can *add* keys to a catalog but cannot translate
them, and a reviewed JSON diff is easier to read than a catalog diff.

```
tools/l10n/*.json                key → {"en": "...", "it": "..."}   (plurals: {"plural": {...}})
tools/l10n/infoplist-app.json    permission texts, app
tools/l10n/infoplist-widget.json permission text, widget
tools/l10n/appshortcuts.json     Siri phrase sets
```

## Adding or changing a string

1. Write it in Portuguese in the code, in one of these forms:
   - SwiftUI: `Text("Salvar")`, `Button("Salvar") { … }`, `Label("Salvar", systemImage: …)`.
     These are `LocalizedStringKey`s and extract on their own.
   - Anything that is a plain `String` (model labels, notification text, accessibility
     strings built in code): `String(localized: "Salvar")`.
   - App Intents and widgets: `LocalizedStringResource` / `IntentDescription` literals.
   - Poster titles: `PosterTitle(localized: "PER\nTO")`. See below.
2. Build, then fold what the compiler found into the catalog:
   `xcodebuild … -derivedDataPath build/i18n build && tools/l10n.py sync`
   (`SWIFT_EMIT_LOC_STRINGS` is on, so each build writes `.stringsdata`). `sync` also runs
   `fill`, which writes explicit pt-BR values: Xcode leaves a key out of `pt-BR.lproj`
   when its value equals the key, and a Portuguese device would then fall back to
   English. Run `tools/l10n.py prune` to drop keys that vanished from the code.
3. Add the English and Italian to a `tools/l10n/*.json` file and run
   `tools/l10n.py merge tools/l10n/model.json tools/l10n/interface.json`.
4. `tools/check-localization.py` must print `0 problems`. It also lints the Swift sources
   for the two traps below.

### The two ways a literal looks localized and is not

SwiftUI localizes a *literal* handed to `Text`, `Button`, `Label`, `Toggle` and the
accessibility modifiers. It does not localize:

- **A ternary of literals**: `Text(saved ? "Remover" : "Salvar")` picks the verbatim
  `String` overload. Write `Text(saved ? String(localized: "Remover") : String(localized: "Salvar"))`.
- **A `String` parameter**: `FactRow(label: "Tipo")` where `label: String` is shown
  verbatim. Either type the parameter `LocalizedStringKey` (the literal then extracts)
  or pass `String(localized:)`.

Having the key in the catalog proves nothing about this: the same text may be extracted
from somewhere else. The only test is to look at the screen in another language, which
is what `tools/l10n-screenshots.sh` is for.

### Poster titles

The big two-line titles (`PosterTitle`) are one catalog entry with a newline between the
lines, so the translator re-cuts the *word* to fill the plate in their language instead
of translating two halves: `"PER\nTO"` is `NEAR\nBY` in English and `VICI\nNO` in Italian.
Keep every line to about five letters at 104 pt; a longer line shrinks to fit. The
current cuts: Nearby `PER/TO` · `NEAR/BY` · `VICI/NO`; Saved `SAL/VAS` · `SAV/ED` ·
`SAL/VATE`; Settings `AJUS/TES` · `SET/TINGS` · `OPZIO/NI`; Reports `RELA/TOS` ·
`REPOR/TS` · `SEGNA/LAZIONI`.

### Vocabulary

| Concept | pt-BR | English | Italian |
| --- | --- | --- | --- |
| a drinking fountain | fonte | fountain | fontanella |
| a community post | relato | report | segnalazione |
| to flag a post | denunciar | flag | segnala |
| a saved fountain | salva | saved | salvata |
| distance measured from | a partir de | from | da |

Italian says *fontanella*, never *fonte* (a spring); *salvate*, not *preferite*, so the
tab, the title and the buttons agree. Italian speaks to the reader as *tu*. Where a
gendered form would be needed for the reader ("sei arrivato/a"), the sentence is
rewritten to avoid it ("Destinazione raggiunta"). English is US spelling (meters,
neighborhood, center).

### Plurals

Counts use catalog plural variations where the noun changes (`%lld avaliações` → "1 rating",
"2 ratings", "1 valutazione", "2 valutazioni", "1 avaliação", "2 avaliações"; `%lld metros`;
`%lld minutos a pé`). A few older sentences branch on `count == 1` in code and carry two
keys (`1 fonte a até 500 m %@.` / `%lld fontes a até 500 m %@.`); each is translated
on its own. Never glue translated pieces into a sentence: give the translator the whole
sentence with the variable inside it, and use positional specifiers (`%1$@`, `%2$@`) in a
translation that needs another word order.

## Numbers, dates, distances

Everything goes through `Shared/Model/Formatting.swift`; nothing hard-codes a locale.
(`Locale(identifier: "pt_BR")` anywhere in `Shared/` or `Toret/` is a bug.)

- Ratings: "4,6" in Portuguese and Italian, "4.6" in English.
- Distances: **metric in every language** ("84 m", "1,2 km"), through
  `DistanceFormat` (`Shared/Model/Formatting.swift`), which every surface uses: rows,
  compass, widgets, Live Activity, Siri. The fountains are in Italy; an American reader
  still needs meters to walk Via Po. It never converts to feet or miles. Spoken forms
  ("84 meters", "1.2 kilometers") are catalog strings with their own plurals.
- Relative times: "há 2 h", "2 hr. ago", "2 h fa", from `RelativeDateTimeFormatter`.
- Clock: 24 h or 12 h as the device is set.
- MapKit's walking instructions arrive already translated by the system. Our own
  fallback sentences are in the catalog.
- Fountain names are data, not interface: they are as mappers wrote them in
  OpenStreetMap (Italian), and a generic name ("Fontanella", "Drinking water",
  "Água potável") is replaced by the street name, in any of the three languages.

## Persisted values are never display text

An enum that is stored must not use its display text as the stored value, or changing
the language (or the wording) loses the user's choice. `MapFilter` stores
`notDry / accessible / bottle / dogs`; its `title` is what the chip says. Builds
before the app was translated stored the Portuguese title, so `MapFilter(stored:)`
still reads those.

## Checking the work

- `tools/check-localization.py` (also run by `LocalizationTests`): every key has `pt-BR`,
  `en` and `it`; nothing is `needs_review`, `new` or stale; plural categories are
  present; format specifiers match the source in every language; every Siri phrase
  names the app.
- `xcodebuild … test -only-testing:ToretTests/LocalizationTests`: language selection
  (German → English, pt-PT → Portuguese, it-CH → Italian), the compiled translations,
  plural rules, locale formatting, the filter migration.
- Looking at it. `tools/l10n-screenshots.sh` launches every screen in every language
  and saves `build/l10n/<lang>/<screen>.png`. Italian runs about 15% longer than
  Portuguese and English about 10% shorter; the poster titles are the hard case.
  For a stress test, double every string:

  ```sh
  LANGS="it" DOUBLE=1 tools/l10n-screenshots.sh
  ```

  which is `-AppleLanguages (it) -NSDoubleLocalizedStrings YES` underneath. Anything
  clipped there will clip for a longer language one day.
- Running the app in a language by hand:
  `xcrun simctl launch <udid> br.tec.nuance.toret -AppleLanguages "(de)"` should come up
  in English; `"(pt-PT)"` in Portuguese.

## Siri and Shortcuts

App Shortcut phrases are not strings but *sets* of phrases, one set per shortcut per
language, each of which must contain the app name (`${applicationName}`). They live in
`AppShortcuts.xcstrings` and are written in `tools/l10n/appshortcuts.json`. Italian
phrases avoid apostrophes ("Dove trovo acqua su Toret") because speech matching is
simpler without them. The shortcut titles and descriptions are ordinary
`LocalizedStringResource`s in `Localizable.xcstrings`.

## App Store

Store copy (name, subtitle, description, keywords, what's new) in the three languages is
in `docs/appstore/metadata.md`. Screenshots are taken per language with the script above
once the screens are final.
