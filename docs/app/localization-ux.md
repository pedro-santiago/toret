# Localization: the user's view

Toret speaks Brazilian Portuguese (`pt-BR`), English (`en`) and Italian (`it`). This page
describes what the person using the app experiences. How strings are extracted, merged
and checked is in [../localization.md](../localization.md); this page does not repeat it.

## Language selection

There is no in-app language picker. iOS picks the first language in the device's
preferred list that the app has (`CFBundleLocalizations` in `project.yml`: `en`, `it`,
`pt-BR`). Because the app has more than one language, iOS Settings > Toret > Language
also appears, so a reader can use Toret in a different language from the phone.

| Device language | Toret speaks |
| --- | --- |
| English (any region) | English |
| Italiano (incl. Svizzera) | Italian |
| Portugues (Brasil or Portugal) | Portuguese |
| Anything else (Deutsch, Espanol, Francais...) | **English** |
| A list "Francais, then Italiano" | Italian |

**Fallback is English, not Portuguese.** The strings in the code are written in
Portuguese, but `CFBundleDevelopmentRegion` and `developmentLanguage` are `en`, so a
German tourist gets English. `ToretTests/LocalizationTests.swift` asserts this table.
Switching the device language takes effect when the app is next launched; a running
app is not re-localised mid-session. The unit tests run in `pt-BR` because they assert
the app's own wording.

Everything is covered by the same three-language catalog: **379 strings, each with
`pt-BR`, `en` and `it`** (`Shared/Resources/Localizable.xcstrings`), plus the permission
texts (`Toret/Resources/InfoPlist.xcstrings`, `ToretWidgets/InfoPlist.xcstrings`) and the
Siri phrase sets (`Toret/Resources/AppShortcuts.xcstrings`). Screens, widgets, the Live
Activity, controls, intents, notifications and VoiceOver strings all go through it.

## What gets translated

| Surface | Example (pt-BR / en / it) |
| --- | --- |
| Tab names | Mapa / Map / Mappa · Perto / Nearby / Vicino · Relatos / Reports / Segnalazioni · Salvas / Saved / Salvate · Ajustes / Settings / Opzioni |
| Water states | Água corrente / Water running / Acqua che scorre · Sem água / No water / Senz’acqua · Sem relato recente / No recent report / Nessuna segnalazione recente |
| Primary action | Traçar rota / Get route / Percorso |
| Fountain kinds | Fonte pública / Public fountain / Fontanella · Bebedouro / Drinking jet / Fontanella a getto · Recarga de garrafa / Bottle refill / Ricarica borracce (Toret is "Toret" everywhere) |
| Compass sentence | Olhe entre ... e ... / Look between ... and ... / Guarda tra ... e ... |
| Hot day | Dia quente: leve água. / Hot day: carry water. / Giornata calda: porta dell’acqua. |
| Arrival | Você chegou / You’ve arrived / Destinazione raggiunta |
| Siri phrases | e.g. "Qual a fonte mais próxima no Toret" / "Nearest fountain in Toret" / "Fontanella più vicina su Toret" (each shortcut has a set of phrases per language, every one containing the app name) |

Landmark names include their article inside the sentence ("a Mole Antonelliana" / "the
Mole Antonelliana" / "la Mole Antonelliana"), so no sentence has to guess a gender.
Ring labels are short capitals: DUOMO, MOLE, SUPERGA, ALPES / ALPS / ALPI, PORTA NUOVA...

## Poster titles are re-cut per language

The big two-line titles are one catalog entry with a line break, so the translator
re-cuts the *word* to fill the plate instead of translating two halves. Values read
from the catalog:

| Screen | pt-BR | en | it |
| --- | --- | --- | --- |
| Perto (tab) | PER / TO | NEAR / BY | VICI / NO |
| Salvas (tab) | SAL / VAS | SAV / ED | SAL / VATE |
| Relatos (tab) | RELA / TOS | REPOR / TS | SEGNA / LAZIONI |
| Ajustes (tab) | AJUS / TES | SET / TINGS | OPZIO / NI |
| Review sheet | AVA / LIAR | RATE / THIS | VALU / TA |
| Review thank-you | OBRI / GADO | THANK / YOU | GRA / ZIE |
| Blocked authors | BLO / QUEIOS | BLOCK / LIST | BLOC / CHI |

Mapa has no poster title. The fountain detail and the compass use the fountain's
own place name as the title, broken after its first word ("Corso / Vittorio Emanuele II",
`Fountain.titleLines`); those are data from OpenStreetMap, not translated. About five
letters per line at 104 pt is the budget; a longer line shrinks to fit. The launch poster
prints TORET.

## Names are data, not interface

Fountain names come from OpenStreetMap contributors and are in Italian. Generic names
("Fontanella", "Drinking water", "Água potável", and so on, in
`Fountain.genericNames`) are replaced by the street name in all three languages.
Street and neighbourhood names are never translated. "Piazza San Carlo", the anchor for
distances when there is no fix, is spelled the same in every language.

The anonymous author handle **"Visitante 4F2A91" is Portuguese in every language**:
`AuthorHandle.make` builds the string in code and the catalog has no entry for it.
This is a known inconsistency.

## Formatting

All through `Shared/Model/Formatting.swift` with the device locale:

| Thing | pt-BR | en | it |
| --- | --- | --- | --- |
| Rating | 4,6 | 4.6 | 4,6 |
| Distance | 84 m, 1,2 km | 84 m, 1.2 km | 84 m, 1,2 km |
| Relative time | há 2 h | 2 hr. ago | 2 h fa |
| Clock | 24 h or 12 h, as the device is set | | |
| Works-notice date (if SMAT is ever on) | day, abbreviated month, year, in Europe/Rome | | |

- **Distances are metric in every language**, never feet or miles: the fountains are in
  Italy and an American still needs metres to walk Via Po (`DistanceFormat`). The units
  "m" and "km" are fixed; below 1000 m there is no decimal, from 9.95 km no decimal.
- Spoken forms ("84 metros", "1,2 quilômetros", "1 quilômetro") are catalog strings with
  their own plurals; counts such as "1 avaliação / 12 avaliações" use catalog plural
  rules.
- MapKit's walking instructions arrive already translated by the system; the app's own
  fallbacks ("Siga na direção da fonte", "Chegada à fonte") are in the catalog.
- Weather degrees are rounded integers (-0 shown as 0).

## Italian and English quirks worth knowing

- Italian says *fontanella*, never *fonte* (a spring), and *salvate*, not *preferite*.
  It addresses the reader as *tu*, and avoids gendered arrival phrases.
- English uses US spelling in the interface, but the units stay metric.
- Italian runs about 15% longer than Portuguese and English about 10% shorter, so
  Italian is the stress case for chips, buttons and the poster titles.

## Persisted values are never display text

Filters are stored by raw value (`notDry`, `accessible`, `bottle`, `dogs`), not by their
label, so changing the language never loses a choice. Older builds that stored the
Portuguese title are still read (`MapFilter(stored:)`).

## Adding a language

Follow [../localization.md](../localization.md): add the language to the three catalogs
and `CFBundleLocalizations`, write the translations in `tools/l10n/*.json`, merge with
`tools/l10n.py`, re-cut the seven poster titles, add a phrase set per Siri shortcut,
extend `LocalizationTests` and run `tools/check-localization.py` until it prints
`0 problems`, then `tools/l10n-screenshots.sh` to look at every screen. Store text lives
in [../appstore/metadata.md](../appstore/metadata.md).

## Gaps

- The author handle is not localised (above).
- The privacy and support pages exist in three languages but are still in the earlier
  visual style ([`DISTRIBUICAO.md`](../../DISTRIBUICAO.md)).
- [../design/poster-system.md](../design/poster-system.md) still says "Plain pt-BR for
  now (en/it to follow)"; that sentence is out of date.
- Right-to-left languages were not considered or tested.
