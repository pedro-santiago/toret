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
2. Build, then fold what the compiler found into the catalog:
   `xcodebuild … -derivedDataPath build/i18n build && tools/l10n.py sync`
   (`SWIFT_EMIT_LOC_STRINGS` is on, so each build writes `.stringsdata`; `sync` marks
   strings that vanished from the code as stale).
3. Add the English and Italian to a `tools/l10n/*.json` file and run
   `tools/l10n.py merge`.
4. `tools/check-localization.py` must print `0 problems`.

Never build a sentence by gluing translated pieces: give the translator the whole
sentence with the variable inside it (`"Relato recente: \(state). Toque…"`), so every
language can order the words its own way. Use positional specifiers (`%1$@`, `%2$@`)
in a translation that needs a different order.

### Plurals

Counts use catalog plural variations, not `if count == 1`. English and Portuguese have
`one` and `other`; Italian has `one`, `many` (only for numbers like 1 000 000, which
share the `other` text here) and `other`. Example: `%lld avaliações` → "1 rating",
"2 ratings", "1 valutazione", "2 valutazioni", "1 avaliação", "2 avaliações".

## Numbers, dates, distances

Everything goes through `Shared/Model/Formatting.swift`; nothing hard-codes a locale.
(`Locale(identifier: "pt_BR")` anywhere in `Shared/` or `Toret/` is a bug.)

- Ratings: "4,6" in Portuguese and Italian, "4.6" in English.
- Distances: **metric in every language** ("84 m", "1,2 km"). The fountains are in
  Italy; an American reader still needs metres to walk Via Po. `Measurement` is used
  with `usage: .asProvided` so it never converts to feet or miles.
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
